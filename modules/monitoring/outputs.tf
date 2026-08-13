output "cloudwatch_alarms_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms"
  value       = aws_sns_topic.cloudwatch_alarms_topic.arn
}

output "remediation_lambda_function_arn" {
  description = "ARN of the incident remediation Lambda function"
  value       = aws_lambda_function.incident_remediation_engine.arn
}

output "remediation_lambda_function_name" {
  description = "Name of the incident remediation Lambda function"
  value       = aws_lambda_function.incident_remediation_engine.function_name
}