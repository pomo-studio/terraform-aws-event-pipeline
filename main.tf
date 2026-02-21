# Event Pipeline Module
# EventBridge + SQS + Lambda with DLQ, retry logic, and CloudWatch alarms

locals {
  # Determine event bus name
  event_bus_name = var.create_event_bus ? aws_cloudwatch_event_bus.this[0].name : "default"
  event_bus_arn  = var.create_event_bus ? aws_cloudwatch_event_bus.this[0].arn : "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"

  # Common tags
  tags = merge(
    {
      Name = var.name
    },
    var.tags
  )
}

# Data sources for current account/region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# Event Bus (conditional)
# ==============================================================================

resource "aws_cloudwatch_event_bus" "this" {
  count = var.create_event_bus ? 1 : 0
  name  = "${var.name}-bus"
  tags  = local.tags
}

# ==============================================================================
# SQS Queues
# ==============================================================================

# Dead Letter Queue (conditional)
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                       = "${var.name}-dlq"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = 30

  tags = local.tags
}

# Main event queue
resource "aws_sqs_queue" "this" {
  name                       = "${var.name}-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds

  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = local.tags
}

# SQS Queue policy to allow EventBridge to send messages
resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.this.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.this.arn
          }
        }
      }
    ]
  })
}

# ==============================================================================
# EventBridge Rule and Target
# ==============================================================================

resource "aws_cloudwatch_event_rule" "this" {
  name           = "${var.name}-rule"
  description    = "Route events to SQS queue"
  event_bus_name = local.event_bus_name
  event_pattern  = jsonencode(var.event_pattern)

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "sqs" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = local.event_bus_name
  target_id      = "SQSQueue"
  arn            = aws_sqs_queue.this.arn

  # Optional: input transformation could go here
}

# ==============================================================================
# Lambda Function (conditional)
# ==============================================================================

resource "aws_lambda_function" "processor" {
  count = var.create_lambda ? 1 : 0

  function_name = "${var.name}-processor"
  role          = aws_iam_role.lambda[0].arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  filename      = var.lambda_code
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  environment {
    variables = var.lambda_environment_variables
  }

  tags = local.tags
}

# Lambda event source mapping: SQS → Lambda
resource "aws_lambda_event_source_mapping" "sqs" {
  count = var.create_lambda ? 1 : 0

  event_source_arn = aws_sqs_queue.this.arn
  function_name    = aws_lambda_function.processor[0].arn
  batch_size       = 10
  enabled          = true
}

# ==============================================================================
# IAM Role for Lambda
# ==============================================================================

resource "aws_iam_role" "lambda" {
  count = var.create_lambda ? 1 : 0

  name = "${var.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# Lambda execution policy (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.create_lambda ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda SQS access policy
resource "aws_iam_role_policy" "lambda_sqs" {
  count = var.create_lambda ? 1 : 0

  name = "${var.name}-lambda-sqs-policy"
  role = aws_iam_role.lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSQSReceive"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.this.arn
      }
    ]
  })
}

# ==============================================================================
# CloudWatch Alarms (conditional)
# ==============================================================================

resource "aws_sns_topic" "alarms" {
  count = var.enable_alarms ? 1 : 0

  name = "${var.name}-alarms"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count = var.enable_alarms && var.alarm_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# DLQ depth alarm
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  count = var.enable_alarms && var.enable_dlq ? 1 : 0

  alarm_name          = "${var.name}-dlq-depth"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.dlq_alarm_threshold
  alarm_description   = "Events are failing processing and landing in DLQ"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[0].name
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = local.tags
}

# Lambda error rate alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_alarms && var.create_lambda ? 1 : 0

  alarm_name          = "${var.name}-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  alarm_description   = "Lambda function is experiencing errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor[0].function_name
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = local.tags
}

# Lambda throttling alarm
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count = var.enable_alarms && var.create_lambda ? 1 : 0

  alarm_name          = "${var.name}-lambda-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Lambda function is being throttled"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor[0].function_name
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]

  tags = local.tags
}
