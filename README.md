# terraform-aws-event-pipeline

## Deprecated

This module is deprecated and maintained for existing consumers only.

For new implementations, use:
- `pomo-studio/event-bus/aws` for shared EventBridge bus infrastructure
- `pomo-studio/event-consumer/aws` for per-service EventBridge -> SQS -> optional Lambda consumers

See [Migration](#migration) for a direct replacement example.

Terraform module for AWS event-driven pipelines — EventBridge → SQS → Lambda with optional DLQ, alarms, and CloudWatch logging.

- Full EventBridge → SQS → Lambda wiring in one module call — no queue policies or IAM to wire manually
- DLQ and retry logic on by default — failed events are preserved, never silently dropped
- CloudWatch alarms for DLQ depth, Lambda errors, and throttles included out of the box
- Least-privilege Lambda IAM role auto-generated and scoped to its own queue only
- Caller owns producers and business logic — module handles all the event routing plumbing

**Registry**: `pomo-studio/event-pipeline/aws`

## Usage

### Basic: EventBridge → SQS

```hcl
module "pipeline" {
  source  = "pomo-studio/event-pipeline/aws"
  version = "~> 1.1"

  name = "prod-order-events"

  event_pattern = {
    source      = ["myapp.orders"]
    detail-type = ["Order Placed"]
  }

  enable_alarms = false
}
```

### Complete: EventBridge → SQS → Lambda + alarms

```hcl
module "pipeline" {
  source  = "pomo-studio/event-pipeline/aws"
  version = "~> 1.1"

  name             = "prod-payment-events"
  create_event_bus = true

  event_pattern = {
    source      = ["myapp.payments"]
    detail-type = ["Payment Processed"]
    detail = {
      status = ["completed", "failed"]
    }
  }

  create_lambda      = true
  lambda_code        = "${path.module}/function.zip"
  lambda_runtime     = "nodejs20.x"
  lambda_timeout     = 30
  lambda_memory_size = 256

  enable_dlq                     = true
  max_receive_count               = 3
  sqs_visibility_timeout_seconds = 180

  enable_alarms = true
  alarm_email   = "alerts@example.com"

  tags = { Environment = "production" }
}
```

## Migration

Replace one `event-pipeline` module call with two explicit module calls:

```hcl
module "bus" {
  source  = "pomo-studio/event-bus/aws"
  version = "~> 1.0"

  providers = {
    aws.primary = aws.primary
    aws.dr      = aws.dr
  }

  name = "prod-payment-events"
}

module "consumer" {
  source  = "pomo-studio/event-consumer/aws"
  version = "~> 1.0"

  providers = {
    aws.primary = aws.primary
    aws.dr      = aws.dr
  }

  name             = "prod-payment-events"
  bus_name_primary = module.bus.bus_name_primary
  bus_name_dr      = module.bus.bus_name_dr

  event_pattern = {
    source      = ["myapp.payments"]
    detail-type = ["Payment Processed"]
  }

  create_lambda      = true
  lambda_code        = "${path.module}/function.zip"
  lambda_runtime     = "nodejs20.x"
  lambda_timeout     = 30
  lambda_memory_size = 256

  enable_alarms = true
  alarm_email   = "alerts@example.com"
}
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | required | Resource naming prefix |
| `event_pattern` | `any` | required | EventBridge event pattern as a map |
| `create_event_bus` | `bool` | `false` | Create a dedicated event bus. If false, uses the default bus |
| `create_lambda` | `bool` | `false` | Create a Lambda processor wired to the SQS queue |
| `lambda_code` | `string` | `null` | Path to Lambda zip (required when `create_lambda = true`) |
| `lambda_handler` | `string` | `"index.handler"` | Lambda handler |
| `lambda_runtime` | `string` | `"nodejs20.x"` | Lambda runtime |
| `lambda_timeout` | `number` | `30` | Lambda timeout in seconds (must be less than `sqs_visibility_timeout_seconds`) |
| `lambda_memory_size` | `number` | `128` | Lambda memory in MB |
| `lambda_environment_variables` | `map(string)` | `{}` | Lambda environment variables |
| `lambda_batch_size` | `number` | `10` | Max SQS records per Lambda invocation (1–10000) |
| `enable_dlq` | `bool` | `true` | Enable Dead Letter Queue |
| `max_receive_count` | `number` | `3` | Receive attempts before moving to DLQ (1–1000) |
| `sqs_visibility_timeout_seconds` | `number` | `180` | SQS visibility timeout — set to at least 6× `lambda_timeout` |
| `dlq_visibility_timeout_seconds` | `number` | `30` | DLQ visibility timeout |
| `sqs_message_retention_seconds` | `number` | `345600` | SQS message retention (default: 4 days) |
| `enable_logging` | `bool` | `true` | Log matched EventBridge events to CloudWatch |
| `enable_alarms` | `bool` | `true` | Enable CloudWatch alarms (DLQ depth, Lambda errors/throttles) |
| `alarm_email` | `string` | `null` | SNS alarm destination (required when `enable_alarms = true`) |
| `dlq_alarm_threshold` | `number` | `1` | DLQ message count that triggers alarm |
| `lambda_error_threshold` | `number` | `1` | Lambda errors per minute that trigger alarm |
| `tags` | `map(string)` | `{}` | Tags applied to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `event_bus_name` | EventBridge bus name (`"default"` if no custom bus) |
| `event_bus_arn` | EventBridge bus ARN |
| `event_rule_name` | EventBridge rule name |
| `event_rule_arn` | EventBridge rule ARN |
| `queue_name` | SQS queue name |
| `queue_arn` | SQS queue ARN |
| `queue_url` | SQS queue URL |
| `dlq_name` | DLQ name (null if disabled) |
| `dlq_arn` | DLQ ARN (null if disabled) |
| `dlq_url` | DLQ URL (null if disabled) |
| `lambda_function_name` | Lambda function name (null if disabled) |
| `lambda_function_arn` | Lambda function ARN (null if disabled) |
| `lambda_role_arn` | Lambda IAM role ARN (null if disabled) |
| `log_group_name` | CloudWatch log group for EventBridge events (null if disabled) |
| `log_group_arn` | CloudWatch log group ARN (null if disabled) |
| `alarm_topic_arn` | SNS alarm topic ARN (null if disabled) |
| `dlq_alarm_name` | DLQ depth alarm name (null if disabled) |
| `lambda_error_alarm_name` | Lambda error alarm name (null if disabled) |

## What it creates

Per module call:
- `aws_cloudwatch_event_rule` — event pattern filter
- `aws_sqs_queue` — main event queue
- `aws_cloudwatch_event_target` — routes matched events to SQS
- SQS queue policy — allows EventBridge to enqueue

Conditional:
- `aws_cloudwatch_event_bus` — custom bus (`create_event_bus = true`)
- `aws_sqs_queue` DLQ + redrive policy (`enable_dlq = true`)
- `aws_lambda_function` + IAM role + event source mapping (`create_lambda = true`)
- `aws_cloudwatch_log_group` — EventBridge event log (`enable_logging = true`)
- `aws_cloudwatch_metric_alarm` × 3 + `aws_sns_topic` (`enable_alarms = true`)

## Design decisions

**EventBridge → SQS over direct invocation** — decouples event producer from processor; SQS absorbs bursts and provides retry semantics independently of Lambda.

**DLQ on by default** — failed events are preserved rather than silently dropped. Drain strategy (reprocess, alert, discard) is the caller's responsibility.

**Alarms on by default** — DLQ depth ≥ 1 and Lambda errors ≥ 1 are treated as incidents. Both thresholds are configurable.

**`lambda_timeout` < `sqs_visibility_timeout_seconds` enforced** — validated at plan time to prevent duplicate processing from visibility timeout expiry during execution.

**Caller owns producers and IAM for them** — `events:PutEvents` permission on the bus is not managed here; the calling module grants it to whatever publishes events.

## Examples

- [`examples/basic`](examples/basic/) — EventBridge → SQS only
- [`examples/complete`](examples/complete/) — full pipeline with Lambda and alarms

## Requirements

| Tool | Version |
|------|---------|
| Terraform | `>= 1.9.0` |
| AWS provider | `~> 5.0` |

## License

MIT
