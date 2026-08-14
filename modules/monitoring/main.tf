# ==============================================================================
# 1. CORE NOTIFICATION INFRASTRUCTURE
# ==============================================================================

resource "aws_sns_topic" "cloudwatch_alarms_topic" {
  name              = "${var.env_prefix}-cloudwatch-alarms"
  display_name      = "${var.env_prefix} CloudWatch Alarms"
  kms_master_key_id = var.sns_kms_key_id

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-cloudwatch-alarms"
    }
  )
}

resource "aws_sns_topic_subscription" "email_subscription" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cloudwatch_alarms_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ==============================================================================
# 2. METRIC ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "${var.env_prefix}-ASG-High-CPU-Utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cpu_evaluation_periods
  datapoints_to_alarm = var.cpu_datapoints_to_alarm
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.cpu_alarm_period
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Alarm when average CPU utilization across Auto Scaling Group '${var.asg_name}' exceeds ${var.cpu_alarm_threshold}%"
  actions_enabled     = true
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms_topic.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms_topic.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-ASG-High-CPU-Alarm"
    }
  )
}

# ==============================================================================
# 3. PROACTIVE AUTOMATED REMEDIATION ENGINE (LAMBDA & COMPONENT HOOKS)
# ==============================================================================

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

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
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DetachInstances"
        ]
        Resource = "*" # Scoped down by ASG ARN if available
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
      }
    ]
  })
}

# Explicit Log Group management to prevent unexpiring CloudWatch logs
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.env_prefix}-incident-remediation-engine"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

# Archive fallback ensures code packages cleanly even during plan step
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  dynamic "source" {
    for_each = fileexists("${path.module}/lambda_function.py") ? [1] : []
    content {
      content  = file("${path.module}/lambda_function.py")
      filename = "lambda_function.py"
    }
  }

  # Fallback code if lambda_function.py is missing locally
  dynamic "source" {
    for_each = fileexists("${path.module}/lambda_function.py") ? [] : [1]
    content {
      content  = "def lambda_handler(event, context):\n    print('Placeholder remediation function')"
      filename = "lambda_function.py"
    }
  }
}

resource "aws_lambda_function" "incident_remediation_engine" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.env_prefix}-incident-remediation-engine"
  role             = aws_iam_role.lambda_remediation_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      TARGET_GROUP_ARN  = var.target_group_arn
      ASG_NAME          = var.asg_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_log_group]

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-incident-remediation-engine"
    }
  )
}

resource "aws_sns_topic_subscription" "lambda_remediation_subscriber" {
  topic_arn = aws_sns_topic.cloudwatch_alarms_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.incident_remediation_engine.arn
}

resource "aws_lambda_permission" "allow_sns_invocation" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_remediation_engine.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cloudwatch_alarms_topic.arn
}