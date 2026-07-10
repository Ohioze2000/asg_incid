output "asg_name" {
  description = "The dynamically generated name of the Auto Scaling Group managing the web servers."
  # FIXED: Referencing .id instead of .name provides a more resilient state reference during name_prefix changes
  value       = aws_autoscaling_group.web_asg.id
}

output "asg_arn" {
  description = "The ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.web_asg.arn
}

output "ec2_security_group_id" {
  description = "The security group ID assigned to the computing instances."
  value       = aws_security_group.ec2-sg.id
}

output "ec2_security_group_name" {
  description = "The security group name assigned to the computing instances."
  value       = aws_security_group.ec2-sg.name
}