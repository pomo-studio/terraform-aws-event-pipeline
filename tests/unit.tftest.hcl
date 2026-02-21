# Unit tests for terraform-aws-event-pipeline
#
# Requires Terraform >= 1.7.0 (mock_provider support)
#
# Before running tests that include Lambda, generate the fixture zip:
#   cd tests/fixtures && zip function.zip index.js
# Or simply: make test

mock_provider "aws" {}

# ==============================================================================
# SQS + EventBridge core
# ==============================================================================

run "default_resources_created" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = false
  }

  assert {
    condition     = aws_sqs_queue.this.name == "test-pipeline-queue"
    error_message = "Main queue must be named {name}-queue"
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) == 1
    error_message = "DLQ must be created by default (enable_dlq defaults to true)"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.name == "test-pipeline-rule"
    error_message = "Event rule must be named {name}-rule"
  }

  assert {
    condition     = length(aws_lambda_function.processor) == 0
    error_message = "Lambda must not be created by default (create_lambda defaults to false)"
  }
}

run "dlq_disabled" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = false
    enable_dlq    = false
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) == 0
    error_message = "DLQ must not be created when enable_dlq=false"
  }
}

run "custom_event_bus" {
  variables {
    name             = "test-pipeline"
    event_pattern    = { source = ["test.app"] }
    enable_alarms    = false
    create_event_bus = true
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) == 1
    error_message = "Custom event bus must be created when create_event_bus=true"
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "test-pipeline-bus"
    error_message = "Event bus must be named {name}-bus"
  }
}

# ==============================================================================
# Logging
# ==============================================================================

run "logging_enabled_creates_target" {
  variables {
    name           = "test-pipeline"
    event_pattern  = { source = ["test.app"] }
    enable_alarms  = false
    enable_logging = true
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.logs) == 1
    error_message = "Logging target must be created when enable_logging=true"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.eventbridge) == 1
    error_message = "Log group must be created when enable_logging=true"
  }

  assert {
    condition     = length(aws_iam_role.eventbridge_logging) == 1
    error_message = "IAM role for logging must be created when enable_logging=true"
  }
}

run "logging_disabled_no_target" {
  variables {
    name           = "test-pipeline"
    event_pattern  = { source = ["test.app"] }
    enable_alarms  = false
    enable_logging = false
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.logs) == 0
    error_message = "Logging target must not be created when enable_logging=false"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.eventbridge) == 0
    error_message = "Log group must not be created when enable_logging=false"
  }
}

# ==============================================================================
# Lambda
# ==============================================================================

run "lambda_created_with_correct_config" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = false
    create_lambda = true
    lambda_code   = "./tests/fixtures/function.zip"
  }

  assert {
    condition     = length(aws_lambda_function.processor) == 1
    error_message = "Lambda must be created when create_lambda=true"
  }

  assert {
    condition     = aws_lambda_function.processor[0].function_name == "test-pipeline-processor"
    error_message = "Lambda must be named {name}-processor"
  }

  assert {
    condition     = length(aws_lambda_event_source_mapping.sqs) == 1
    error_message = "SQS event source mapping must be created when create_lambda=true"
  }

  assert {
    condition     = contains(tolist(aws_lambda_event_source_mapping.sqs[0].function_response_types), "ReportBatchItemFailures")
    error_message = "Event source mapping must enable ReportBatchItemFailures for partial batch failure support"
  }
}

run "lambda_iam_policy_includes_batch_visibility" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = false
    create_lambda = true
    lambda_code   = "./tests/fixtures/function.zip"
  }

  assert {
    condition = contains(
      jsondecode(aws_iam_role_policy.lambda_sqs[0].policy).Statement[0].Action,
      "sqs:ChangeMessageVisibilityBatch"
    )
    error_message = "Lambda IAM policy must include sqs:ChangeMessageVisibilityBatch for batch failure handling"
  }
}

run "lambda_batch_size_configurable" {
  variables {
    name              = "test-pipeline"
    event_pattern     = { source = ["test.app"] }
    enable_alarms     = false
    create_lambda     = true
    lambda_code       = "./tests/fixtures/function.zip"
    lambda_batch_size = 100
  }

  assert {
    condition     = aws_lambda_event_source_mapping.sqs[0].batch_size == 100
    error_message = "Batch size must match lambda_batch_size variable"
  }
}

# ==============================================================================
# Alarms
# ==============================================================================

run "alarms_created_when_enabled" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = true
    alarm_email   = "alerts@example.com"
    enable_dlq    = true
  }

  assert {
    condition     = length(aws_sns_topic.alarms) == 1
    error_message = "SNS topic must be created when enable_alarms=true"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.dlq_depth) == 1
    error_message = "DLQ depth alarm must be created when enable_alarms=true and enable_dlq=true"
  }
}

run "alarms_not_created_when_disabled" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = false
  }

  assert {
    condition     = length(aws_sns_topic.alarms) == 0
    error_message = "SNS topic must not be created when enable_alarms=false"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.dlq_depth) == 0
    error_message = "Alarms must not be created when enable_alarms=false"
  }
}

# ==============================================================================
# Validation rules
# ==============================================================================

run "validation_lambda_code_required" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = false
    create_lambda = true
    lambda_code   = null
  }

  expect_failures = [var.lambda_code]
}

run "validation_alarm_email_required" {
  variables {
    name          = "test-pipeline"
    event_pattern = { source = ["test.app"] }
    enable_alarms = true
    alarm_email   = null
  }

  expect_failures = [var.alarm_email]
}

run "validation_batch_size_minimum" {
  variables {
    name              = "test-pipeline"
    event_pattern     = { source = ["test.app"] }
    enable_alarms     = false
    lambda_batch_size = 0
  }

  expect_failures = [var.lambda_batch_size]
}

run "validation_batch_size_maximum" {
  variables {
    name              = "test-pipeline"
    event_pattern     = { source = ["test.app"] }
    enable_alarms     = false
    lambda_batch_size = 10001
  }

  expect_failures = [var.lambda_batch_size]
}

run "validation_max_receive_count_range" {
  variables {
    name              = "test-pipeline"
    event_pattern     = { source = ["test.app"] }
    enable_alarms     = false
    max_receive_count = 0
  }

  expect_failures = [var.max_receive_count]
}
