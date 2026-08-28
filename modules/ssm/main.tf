resource "aws_ssm_parameter" "cw_agent_config" {
  name        = var.ssm_parameter_name
  description = "CloudWatch Agent configuration for ASG Webservers"
  type        = "String"
  value       = file(var.cw_agent_config_path)

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-cw-agent-config"
    }
  )
}