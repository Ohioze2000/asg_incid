variable "env_prefix" {
  type        = string
  description = "Deployment environment prefix (e.g. dev, staging, prod)"
}

variable "ssm_parameter_name" {
  type        = string
  description = "The name of the SSM parameter for the CloudWatch agent config"
  default     = "/asg-webserver/cloudwatch-agent-config"
}

variable "cw_agent_config_path" {
  type        = string
  description = "Relative or absolute path to the amazon-cloudwatch-agent.json file"
  default     = "amazon-cloudwatch-agent.json"
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}