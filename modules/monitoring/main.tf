# ==============================================================================
# 1. CORE NOTIFICATION INFRASTRUCTURE
# ==============================================================================

resource "aws_sns_topic" "cloudwatch_alarms_topic" {
  name         = "${var.env_prefix}-cloudwatch-alarms"
  display_name = "${var.env_prefix} CloudWatch Alarms"

  tags = {
    Name = "${var.env_prefix}-cloudwatch-alarms"
  }
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.cloudwatch_alarms_topic.arn
  protocol  = "email"
  endpoint  = "ohiozeberyl2000@gmail.com" 
}

# ==============================================================================
# 2. METRIC ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "${var.env_prefix}-ASG-High-CPU-Utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 
  statistic           = "Average"
  threshold           = 80 
  alarm_description   = "Alarm when average CPU utilization across the ASG exceeds 80%"
  actions_enabled     = true

  # FIXED: Cleaned up map closure and consolidated actions to the main topic
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms_topic.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms_topic.arn]

  tags = {
    Name = "${var.env_prefix}-ASG-High-CPU-Alarm"
  }
}

# ==============================================================================
# 3. PROACTIVE AUTOMATED REMEDIATION ENGINE (LAMBDA & COMPONENT HOOKS)
# ==============================================================================

# IAM Execution Role for the Remediation Lambda
resource "aws_iam_role" "lambda_remediation_role" {
  name = "${var.env_prefix}-lambda-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attaching AWS Managed Basic Execution policy for basic logging
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Inline Remediation Engine Permissions (Heal ASG, Quarantine and Tag EC2s)
resource "aws_iam_role_policy" "lambda_remediation_permissions" {
  name = "${var.env_prefix}-lambda-remediation-permissions"
  role = aws_iam_role.lambda_remediation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth",
          "autoscaling:DetachInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:CreateTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Package the python script zip file automatically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# The Remediation Engine Lambda Function
resource "aws_lambda_function" "incident_remediation_engine" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.env_prefix}-incident-remediation-engine"
  role             = aws_iam_role.lambda_remediation_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      TARGET_GROUP_ARN  = var.target_group_arn
      ASG_NAME          = var.asg_name
    }
  }
}

# The Subscription Bridge: Connects the CloudWatch Alarm Topic to Lambda
resource "aws_sns_topic_subscription" "lambda_remediation_subscriber" {
  topic_arn = aws_sns_topic.cloudwatch_alarms_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.incident_remediation_engine.arn
}

# Explicitly grant SNS authority to invoke your self-healing function
resource "aws_lambda_permission" "allow_sns_invocation" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_remediation_engine.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cloudwatch_alarms_topic.arn
}