# Output values for Event Pipeline module
# Expose all important ARNs, IDs, and endpoints

output "event_bus_name" {
  description = "Name of the EventBridge event bus (or 'default')"
  value       = local.event_bus_name
}

output "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  value       = local.event_bus_arn
}

output "event_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.name
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.arn
}

output "queue_name" {
  description = "Name of the main SQS queue"
  value       = aws_sqs_queue.this.name
}

output "queue_arn" {
  description = "ARN of the main SQS queue"
  value       = aws_sqs_queue.this.arn
}

output "queue_url" {
  description = "URL of the main SQS queue"
  value       = aws_sqs_queue.this.url
}

output "dlq_name" {
  description = "Name of the Dead Letter Queue (null if disabled)"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].name : null
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue (null if disabled)"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue (null if disabled)"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}

output "lambda_function_name" {
  description = "Name of the Lambda function (null if disabled)"
  value       = var.create_lambda ? aws_lambda_function.processor[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function (null if disabled)"
  value       = var.create_lambda ? aws_lambda_function.processor[0].arn : null
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role (null if disabled)"
  value       = var.create_lambda ? aws_iam_role.lambda[0].arn : null
}

output "log_group_name" {
  description = "CloudWatch log group for EventBridge events (null if logging disabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.eventbridge[0].name : null
}

output "log_group_arn" {
  description = "CloudWatch log group ARN for EventBridge events (null if logging disabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.eventbridge[0].arn : null
}

output "alarm_topic_arn" {
  description = "ARN of the SNS topic for alarms (null if disabled)"
  value       = var.enable_alarms ? aws_sns_topic.alarms[0].arn : null
}

output "dlq_alarm_name" {
  description = "Name of the DLQ depth alarm (null if disabled)"
  value       = var.enable_alarms && var.enable_dlq ? aws_cloudwatch_metric_alarm.dlq_depth[0].alarm_name : null
}

output "lambda_error_alarm_name" {
  description = "Name of the Lambda error alarm (null if disabled)"
  value       = var.enable_alarms && var.create_lambda ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}
