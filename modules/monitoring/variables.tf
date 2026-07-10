variable "env_prefix" {
  type        = string
  description = "The environment environment prefix (e.g., dev, prod)"
}

variable "asg_name" {
  type        = string
  description = "The name of the Auto Scaling Group to monitor and remediate"
}

#  Brat-new configuration dependencies required by the automation engine:

variable "target_group_arn" {
  type        = string
  description = "The ARN of the ALB Target Group to query for unhealthy application instances"
}

variable "slack_webhook_url" {
  type        = string
  description = "The secure Slack incoming webhook URL used to post incident reports"
  sensitive   = true # Masking the value in your terminal outputs for security
}