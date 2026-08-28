output "ssm_parameter_name" {
  value       = aws_ssm_parameter.cw_agent_config.name
  description = "Name of the SSM Parameter holding CloudWatch agent config"
}

output "ssm_parameter_arn" {
  value       = aws_ssm_parameter.cw_agent_config.arn
  description = "ARN of the SSM Parameter holding CloudWatch agent config"
}