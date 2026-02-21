# Input variables for Event Pipeline module
# DRY: All configurable, sensible defaults, validation where needed

variable "name" {
  description = "Resource naming prefix (e.g., 'prod-order-events')"
  type        = string
}

variable "event_pattern" {
  description = "EventBridge event pattern as a map/object. See AWS docs for pattern syntax."
  type        = any
  # Example:
  # {
  #   source      = ["myapp.orders"]
  #   detail-type = ["Order Placed"]
  # }
}

variable "create_event_bus" {
  description = "Create a custom event bus. If false, uses the default event bus."
  type        = bool
  default     = false
}

variable "create_lambda" {
  description = "Create a Lambda function to process events from SQS"
  type        = bool
  default     = false
}

variable "lambda_code" {
  description = "Path to Lambda deployment package zip file (required if create_lambda=true)"
  type        = string
  default     = null
}

variable "lambda_handler" {
  description = "Lambda function handler (e.g., 'index.handler')"
  type        = string
  default     = "index.handler"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (must be less than SQS visibility timeout)"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 128
}

variable "lambda_environment_variables" {
  description = "Environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

variable "enable_dlq" {
  description = "Enable Dead Letter Queue for failed events"
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Max receives before sending to DLQ (1-1000)"
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "sqs_visibility_timeout_seconds" {
  description = "SQS visibility timeout in seconds (should be 6x Lambda timeout)"
  type        = number
  default     = 180
}

variable "sqs_message_retention_seconds" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 345600 # 4 days
}

variable "enable_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address for alarm notifications (required if enable_alarms=true)"
  type        = string
  default     = null
}

variable "dlq_alarm_threshold" {
  description = "DLQ depth alarm threshold (messages in DLQ)"
  type        = number
  default     = 1
}

variable "lambda_error_threshold" {
  description = "Lambda error rate alarm threshold (errors per minute)"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
