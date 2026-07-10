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

variable "vpc_id" {
  type = string
  description = "The ID of the VPC to which network resources will be attached."
}


