output "event_bus_name" {
  description = "EventBridge event bus name"
  value       = module.event_pipeline.event_bus_name
}

output "event_rule_name" {
  description = "EventBridge rule name"
  value       = module.event_pipeline.event_rule_name
}

output "queue_url" {
  description = "Main SQS queue URL"
  value       = module.event_pipeline.queue_url
}

output "dlq_url" {
  description = "Dead Letter Queue URL"
  value       = module.event_pipeline.dlq_url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = module.event_pipeline.lambda_function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = module.event_pipeline.lambda_function_arn
}

output "alarm_topic_arn" {
  description = "SNS topic for alarms"
  value       = module.event_pipeline.alarm_topic_arn
}
