output "alb_security_group_id" {
  description = "The ID of the Security Group attached to the ALB."
  value       = aws_security_group.alb-sg.id
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.app-alb.dns_name
}

output "alb_hosted_zone_id" {
  description = "The AWS-managed hosted zone ID for the ALB. Cleanly maps into your DNS routing module."
  # FIXED: Matches output naming convention to input maps, avoiding schema confusion
  value       = aws_lb.app-alb.zone_id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer."
  value       = aws_lb.app-alb.arn
}

output "target_group_arn" {
  description = "The ARN of the Target Group. The ASG will use this to register instances."
  value       = aws_lb_target_group.app-tg.arn
}