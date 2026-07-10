#
variable "vpc_cidr_block"{
  type = string
  description = "VPC CIDR BLOCK"
}
variable "env_prefix"{
  type = string
  description = "ENVIRONMENT PREFIX"
}
variable "az_count" {
  default = 2
  type = number
}
variable "my_ip"{
  type = string
  description = "MY IP"
}
variable "instance_type"{
  type = string
  description = "INSTANCE TYPE"
}
variable "public_key_content"{
  type = string
  description = "The raw content of the public SSH key."
}
variable "domain_name"{
  description = "The root domain name to register (must already be registered with a registrar)"
  type        = string
}
variable "image_name" {
  type        = string  # <-- Added type declaration
  description = "The AMI ID or name to use for the EC2 instances." # <-- Added a helpful description
}

variable "desired_capacity" {
  description = "Number of instances to run at all times"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 4
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "slack_webhook_url" {
  type        = string
  description = "The secure Slack incoming webhook URL used to post incident reports and for automated remediation alerting"
  sensitive   = true # Masking the value in your terminal outputs for security
}