# ==============================================================================
# --- Load Balancer Outputs ---
# ==============================================================================

output "alb_dns" {
  description = "The DNS name of the Application Load Balancer."
  value       = module.my-alb.alb_dns_name
}

output "website_url" {
  description = "The HTTPS URL of the deployed website."
  value       = "https://${var.domain_name}"
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer."
  value       = module.my-alb.alb_arn
}

output "alb_hosted_zone_id" {
  description = "The Hosted Zone ID of the ALB (for Route 53 alias records)."
  value       = module.my-alb.alb_hosted_zone_id
}

# --- QUALITY GATE PIPELINE REQUIREMENTS ---
output "target_group_arn" {
  description = "The ARN of the target group to verify instance health states in our Python Quality Gate."
  value       = module.my-alb.target_group_arn  # Assumes your ALB module exposes its target group ARN
}

# ==============================================================================
# --- Compute / Auto Scaling Outputs ---
# ==============================================================================

output "asg_name" {
  description = "The name of the Auto Scaling Group managing the web servers."
  value       = module.my-server.asg_name
}

# --- QUALITY GATE PIPELINE REQUIREMENTS ---
output "ec2_security_group_id" {
  description = "The security group attached to the EC2 instances to check for compliance rule drift."
  value       = module.my-server.ec2_security_group_id # Assumes your compute module exposes the backend SG ID
}

# ==============================================================================
# --- Network Outputs ---
# ==============================================================================

output "vpc_id" {
  description = "The ID of the created VPC."
  value       = aws_vpc.my-vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.my-network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = module.my-network.private_subnet_ids
}

# ==============================================================================
# --- DNS & SSL Outputs ---
# ==============================================================================

output "route53_zone_id" {
  description = "The ID of the Route 53 Hosted Zone."
  value       = module.my-dns.zone_id
}

output "route53_zone_name" {
  description = "The name of the Route 53 Hosted Zone."
  value       = module.my-dns.zone_name
}

output "name_servers" {
  description = "DNS Name Servers for the registrar."
  value       = module.my-dns.name_servers
}

output "validated_certificate_arn" {
  description = "The ARN of the validated ACM certificate."
  value       = aws_acm_certificate_validation.cert_validation.certificate_arn
}

# ==============================================================================
# --- Monitoring ---
# ==============================================================================

output "cloudwatch_alarms_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms."
  value       = module.my-monitoring.cloudwatch_alarms_topic_arn
}