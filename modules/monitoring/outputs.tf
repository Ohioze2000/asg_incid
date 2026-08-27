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

output "high_cpu_alarm_arn" {
  description = "ARN of the High CPU alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu_alarm.arn
}

output "high_disk_alarm_arn" {
  description = "ARN of the High Disk Usage alarm"
  value       = length(aws_cloudwatch_metric_alarm.high_disk_alarm) > 0 ? aws_cloudwatch_metric_alarm.high_disk_alarm[0].arn : null
}

output "log_error_alarm_arn" {
  description = "ARN of the Log Error alarm"
  value       = length(aws_cloudwatch_metric_alarm.app_error_alarm) > 0 ? aws_cloudwatch_metric_alarm.app_error_alarm[0].arn : null
}