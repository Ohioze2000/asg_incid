#
variable "domain_name"{
  description = "The root domain name to register (must already be registered with a registrar)"
  type        = string
}

variable "alb_dns_name" {
  description = "The DNS name of the ALB to point records to."
  type        = string
}

variable "alb_zone_id" {
  description = "The Route 53 Hosted Zone ID of the Application Load Balancer."
  type        = string
}

variable "env_prefix" {
  description = "Prefix for resources created by the DNS module."
  type        = string
}

