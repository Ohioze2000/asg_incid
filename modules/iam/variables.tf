variable "env_prefix"{
  type = string
  description = "ENVIRONMENT PREFIX"
}

variable "iam_instance_profile_name" {
  type        = string
  description = "The name of the IAM instance profile to attach to the EC2 instances."
}