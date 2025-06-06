output "lambda_function_arn" {
  description = "ARN of the EC2 shutdown Lambda function"
  value       = aws_lambda_function.ec2_shutdown.arn
}

output "lambda_function_name" {
  description = "Name of the EC2 shutdown Lambda function"
  value       = aws_lambda_function.ec2_shutdown.function_name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ec2_shutdown_logs.name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.ec2_shutdown_schedule.name
}

output "iam_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}