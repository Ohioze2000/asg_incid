output "iam_instance_profile_name" {
    description = "The name of the IAM Instance Profile created for EC2 instances."
    value = aws_iam_instance_profile.ec2_ssm_profile.name
}

output "iam_instance_profile_arn" {
     description = "The ARN of the IAM Instance Profile created for EC2 instances."
     value       = aws_iam_instance_profile.ec2_ssm_profile.arn
}