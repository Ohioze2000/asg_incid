variable "aws_region" {
  type        = string
  description = "AWS region for infrastructure deployment"
  default     = "us-east-1"
}

variable "env_prefix" {
  type        = string
  description = "Environment prefix used for resource naming (e.g., dev, staging, prod)"
}

variable "vpc_cidr_block" {
  type        = string
  description = "Base IPv4 CIDR block for the primary VPC"
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones to deploy subnets into"
  default     = 2
}

variable "my_ip" {
  type        = string
  description = "Administrator IP address for restricted access (CIDR format)"
  default     = "0.0.0.0/0"
}

variable "domain_name" {
  type        = string
  description = "The registered domain name for DNS routing and ACM SSL certification"
}

variable "image_name" {
  type        = string
  description = "AMI search pattern for EC2 instance launch template"
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for Auto Scaling Group nodes"
  default     = "t3.micro"
}

variable "public_key_content" {
  type        = string
  description = "Raw public SSH key content for direct host access. Leave empty if using SSM"
  default     = ""
}

variable "desired_capacity" {
  type        = number
  description = "Target number of instances in the Auto Scaling Group"
  default     = 2
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances in the Auto Scaling Group"
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances in the Auto Scaling Group"
  default     = 4
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack Webhook URL for CloudWatch incident alerting and remediation events"
  sensitive   = true
}

# ==============================================================================
# LOGGING & OBSERVABILITY VARIABLES
# ==============================================================================

variable "default_log_retention_days" {
  type        = number
  description = "Default CloudWatch Log Group retention in days"
  default     = 30
}

variable "log_groups" {
  type = map(object({
    retention_in_days = optional(number)
    kms_key_id        = optional(string)
  }))
  description = "Map of CloudWatch log group definitions"
  default     = {}
}

variable "metric_filters" {
  type = map(object({
    log_group_key    = string
    pattern          = string
    metric_name      = string
    metric_namespace = string
    metric_value     = optional(string, "1")
    default_value    = optional(string, "0")
  }))
  description = "Map of log metric filters to convert logs into custom CloudWatch metrics"
  default     = {}
}

variable "app_alarms" {
  type = map(object({
    metric_name         = string
    metric_namespace    = string
    threshold           = number
    is_custom_metric    = optional(bool, true)
    comparison_operator = optional(string, "GreaterThanOrEqualToThreshold")
    evaluation_periods  = optional(number, 1)
    period              = optional(number, 60)
    statistic           = optional(string, "Sum")
    description         = optional(string)
    treat_missing_data  = optional(string, "notBreaching")
    dimensions          = optional(map(string), {})
  }))
  description = "Map of custom CloudWatch application alarms"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Resource tags applied across all deployed modules"
  default     = {}
}