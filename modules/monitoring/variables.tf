variable "env_prefix" {
  type        = string
  description = "Environment prefix used for naming resources (e.g., dev, staging, prod)"
}

variable "asg_name" {
  type        = string
  description = "The name of the Auto Scaling Group to monitor and remediate"
}

variable "target_group_arn" {
  type        = string
  description = "The ARN of the ALB Target Group to query for unhealthy application instances"
}

variable "slack_webhook_url" {
  type        = string
  description = "The secure Slack incoming webhook URL used to post incident reports"
  sensitive   = true
}

variable "alert_email" {
  type        = string
  description = "Optional email address to subscribe to SNS alarm notifications"
  default     = ""
}

variable "sns_kms_key_id" {
  type        = string
  description = "KMS Key ID or ARN to encrypt the SNS Topic at rest"
  default     = null
}

# --- CPU Alarm Variables ---
variable "cpu_alarm_threshold" {
  type        = number
  description = "Average CPU threshold percent to trigger alarm"
  default     = 80
}

variable "cpu_evaluation_periods" {
  type        = number
  description = "The number of periods over which data is compared against the threshold"
  default     = 2
}

variable "cpu_datapoints_to_alarm" {
  type        = number
  description = "The number of datapoints within the evaluation period that must be breaching to trigger the alarm"
  default     = 2
}

variable "cpu_alarm_period" {
  type        = number
  description = "The period in seconds over which the specified statistic is applied"
  default     = 300
}

# --- Disk Alarm Variables ---
variable "enable_disk_alarm" {
  type        = bool
  description = "Whether to deploy the high disk usage alarm"
  default     = true
}

variable "disk_alarm_threshold" {
  type        = number
  description = "Root disk usage threshold percentage to trigger alarm"
  default     = 85
}

variable "disk_evaluation_periods" {
  type        = number
  description = "Evaluation periods for disk alarm"
  default     = 2
}

variable "disk_alarm_period" {
  type        = number
  description = "Period in seconds for disk alarm evaluation"
  default     = 300
}

# --- Log Error Alarm Variables ---
variable "enable_log_error_alarm" {
  type        = bool
  description = "Whether to enable application log error monitoring"
  default     = true
}

variable "app_log_group_name" {
  type        = string
  description = "Name of the CloudWatch log group storing application logs"
  default     = "/ec2/app-logs"
}

variable "log_error_pattern" {
  type        = string
  description = "Metric filter pattern to search for error terms in logs"
  default     = "?ERROR ?Error ?error ?500 ?EXCEPTION ?Exception"
}

variable "log_error_threshold" {
  type        = number
  description = "Number of log error occurrences in period to trigger alarm"
  default     = 5
}

variable "log_error_alarm_period" {
  type        = number
  description = "Evaluation window in seconds for error log frequency"
  default     = 60
}

# --- General Variables ---
variable "log_retention_in_days" {
  type        = number
  description = "CloudWatch Log Group retention period in days for the remediation Lambda"
  default     = 14
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to all module resources"
  default     = {}
}