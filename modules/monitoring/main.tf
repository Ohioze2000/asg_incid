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

# SNS Topic Policy allowing CloudWatch to publish alarms securely
resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.cloudwatch_alarms_topic.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.cloudwatch_alarms_topic.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudwatch:*:*:alarm:${var.env_prefix}-*"
          }
        }
      }
    ]
  })
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

# --- HIGH CPU ALARM ---
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

# --- HIGH DISK UTILIZATION ALARM ---
resource "aws_cloudwatch_metric_alarm" "high_disk_alarm" {
  count               = var.enable_disk_alarm ? 1 : 0
  alarm_name          = "${var.env_prefix}-ASG-High-Disk-Utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.disk_evaluation_periods
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = var.disk_alarm_period
  statistic           = "Average"
  threshold           = var.disk_alarm_threshold
  alarm_description   = "Alarm when root disk utilization exceeds ${var.disk_alarm_threshold}%"
  actions_enabled     = true
  treat_missing_data  = "notBreaching"

  dimensions = {
    path = "/"
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms_topic.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms_topic.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-ASG-High-Disk-Alarm"
    }
  )
}

# ==============================================================================
# 3. LOG ERROR MONITORING (FILTER + ALARM)
# ==============================================================================

resource "aws_cloudwatch_log_metric_filter" "app_error_filter" {
  count          = var.enable_log_error_alarm ? 1 : 0
  name           = "${var.env_prefix}-app-error-filter"
  pattern        = var.log_error_pattern
  log_group_name = var.app_log_group_name

  metric_transformation {
    name          = "${var.env_prefix}-AppErrorCount"
    namespace     = "CustomAppMetrics"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_error_alarm" {
  count               = var.enable_log_error_alarm ? 1 : 0
  alarm_name          = "${var.env_prefix}-App-Log-Errors-Spike"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.app_error_filter[0].metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.app_error_filter[0].metric_transformation[0].namespace
  period              = var.log_error_alarm_period
  statistic           = "Sum"
  threshold           = var.log_error_threshold
  alarm_description   = "Alarm when application error occurrences in log group '${var.app_log_group_name}' exceed ${var.log_error_threshold}"
  actions_enabled     = true
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudwatch_alarms_topic.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms_topic.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-App-Log-Errors-Alarm"
    }
  )
}

# ==============================================================================
# 4. PROACTIVE AUTOMATED REMEDIATION ENGINE (LAMBDA & COMPONENT HOOKS)
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

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-lambda-remediation-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_remediation_policy" {
  name = "${var.env_prefix}-lambda-remediation-policy"
  role = aws_iam_role.lambda_remediation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DetachInstances",
          "ec2:DescribeInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.env_prefix}-incident-remediation-engine"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

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
      ENV_PREFIX        = var.env_prefix
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