variable "vpc_id" {
  type        = string # Added type
  description = "The ID of the VPC where web servers will be deployed."
}

variable "env_prefix"{
  type = string
  description = "ENVIRONMENT PREFIX"
}

variable "az_count" {
  default = 2
  type = number
  description = "The number of Availability Zones to deploy instances into."
}

variable "public_key_content"{
  type = string
  description = "The raw content of the public SSH key."
}

variable "image_name" {
  type = string

}

variable "instance_type"{
  type = string
  description = "INSTANCE TYPE"
}

#variable "subnet_id" {}

variable "alb_security_group_id" { 
  description = "The ID of the ALB's security group to allow ingress from."
  type        = string
}

variable "private_subnet_ids" { 
  type = list(string) 
  description = "A list of private subnet IDs where EC2 instances will be launched."
}

variable "iam_instance_profile_name" {
  type        = string
  description = "The name of the IAM instance profile to attach to the EC2 instances."
}

variable "target_group_arn" {
  description = "The ARN of the ALB target group for ASG registration"
  type        = string
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "min_size" {
  type    = number
  default = 2
}