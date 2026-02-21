# terraform-aws-event-pipeline

Opinionated Terraform module for AWS event-driven architectures.

**Registry**: `pomo-studio/event-pipeline/aws`

> 📚 **New to event-driven architectures?** Start with the [Getting Started Guide](docs/getting-started.md)
>
> 🏗️ **Want to understand the design?** Read the [Architecture Documentation](docs/architecture.md)

## Module scope

This module manages the **routing and processing infrastructure** — the plumbing
between your event source and your business logic. It does not manage what
produces events or what your Lambda code does.

See [Architecture Documentation](docs/architecture.md) for full diagrams and design details.

### What you bring

| Your responsibility | Detail |
|---------------------|--------|
| **Event source** | Your app, an AWS service (S3, RDS, etc.), or a partner integration — whatever calls `events:PutEvents` |
| **IAM for your producer** | The role/policy that allows your event source to call `events:PutEvents` on the bus |
| **The event bus** | The default EventBridge bus exists in every AWS account; optionally this module creates a custom one via `create_event_bus = true` |
| **Lambda function code** | You write the handler and provide the zip path via `lambda_code`; the module deploys and wires it |
| **DLQ drain strategy** | When events land in the DLQ, you decide whether to reprocess them, alert on them, or discard them |

### What this module brings

| Module responsibility | Detail |
|-----------------------|--------|
| **EventBridge rule** | Pattern matching — which events get routed |
| **EventBridge → SQS wiring** | Target, queue policy, IAM |
| **SQS queue + DLQ** | Buffering, retry logic, redrive policy |
| **SQS → Lambda wiring** | Event source mapping, batch size, partial failure reporting |
| **Lambda IAM role** | Least-privilege — only the permissions needed to read from its queue |
| **CloudWatch alarms** | DLQ depth, Lambda errors, Lambda throttles → SNS |
| **EventBridge logging** | All matched events captured to CloudWatch Logs |

### EventBridge bus vs. rule

Every AWS account already has a default EventBridge bus. This module creates
the **rule** on top of it — the pattern filter that routes matching events to
SQS. Set `create_event_bus = true` for a dedicated bus when you want isolation
between workloads or environments.

Publishing events (`events:PutEvents`) and the IAM permissions for it remain
the caller's responsibility.

## What it creates

**Always:**
- `aws_cloudwatch_event_rule` — Pattern matching for events
- `aws_sqs_queue` — Main event queue with configurable retention
- `aws_cloudwatch_event_target` — Routes matched events to SQS
- SQS queue policy — Allows EventBridge to send messages
- `aws_cloudwatch_log_group` — Captures EventBridge events for debugging (when `enable_logging = true`)

**Conditional:**
- `aws_cloudwatch_event_bus` — Custom event bus (when `create_event_bus = true`)
- `aws_sqs_queue` (DLQ) — Dead Letter Queue for failed events (when `enable_dlq = true`)
- `aws_lambda_function` — Event processor (when `create_lambda = true`)
- `aws_lambda_event_source_mapping` — Polls SQS and invokes Lambda
- `aws_iam_role` — Least-privilege role for Lambda execution
- `aws_cloudwatch_metric_alarm` — DLQ depth alarm (when `enable_alarms = true`)
- `aws_cloudwatch_metric_alarm` — Lambda error/throttle alarms
- `aws_sns_topic` — Alarm notifications

## Usage

### Basic: EventBridge → SQS

```hcl
module "pipeline" {
  source  = "pomo-studio/event-pipeline/aws"
  version = "~> 1.0"

  name = "prod-order-events"

  event_pattern = {
    source      = ["myapp.orders"]
    detail-type = ["Order Placed"]
  }

  create_lambda = false  # Just queue events
  enable_dlq    = true   # Enable retry + DLQ
  enable_alarms = false  # No alarms for simple use

  tags = { Environment = "production" }
}
```

### Complete: EventBridge → SQS → Lambda + Alarms

```hcl
module "pipeline" {
  source  = "pomo-studio/event-pipeline/aws"
  version = "~> 1.0"

  name             = "prod-payment-events"
  create_event_bus = true  # Isolated event bus

  event_pattern = {
    source      = ["myapp.payments"]
    detail-type = ["Payment Processed"]
    detail = {
      status = ["completed", "failed"]
      amount = { numeric = [">", 100] }
    }
  }

  # Lambda processor
  create_lambda    = true
  lambda_code      = "${path.module}/function.zip"
  lambda_handler   = "index.handler"
  lambda_runtime   = "nodejs20.x"
  lambda_timeout   = 30
  lambda_memory_size = 256

  # Retry logic
  enable_dlq           = true
  max_receive_count    = 3
  sqs_visibility_timeout_seconds = 180  # 6x Lambda timeout

  # Monitoring
  enable_alarms         = true
  alarm_email           = "alerts@example.com"
  dlq_alarm_threshold   = 1
  lambda_error_threshold = 1

  tags = { Environment = "production" }
}
```

## Key outputs

| Output | Description |
|--------|-------------|
| `queue_url` | Main SQS queue URL (consume from here) |
| `queue_arn` | Main SQS queue ARN |
| `dlq_url` | Dead Letter Queue URL (null if disabled) |
| `event_rule_name` | EventBridge rule name |
| `event_bus_name` | Event bus name (or "default") |
| `log_group_name` | CloudWatch log group for events (null if logging disabled) |
| `lambda_function_name` | Lambda function name (null if disabled) |
| `alarm_topic_arn` | SNS topic for alarms (null if disabled) |

## Event Pattern Examples

```hcl
# Match all events from a source
event_pattern = {
  source = ["myapp.users"]
}

# Match specific event types
event_pattern = {
  source      = ["myapp.orders"]
  detail-type = ["Order Placed", "Order Updated"]
}

# Match with content filtering
event_pattern = {
  source      = ["myapp.payments"]
  detail-type = ["Payment Processed"]
  detail = {
    status = ["failed"]
    amount = { numeric = [">=", 500] }
  }
}
```

## Debugging and Monitoring

### Viewing Events

When `enable_logging = true`, all matched events are sent to CloudWatch Logs:

```bash
# View the log group
aws logs tail /aws/events/prod-order-events --follow

# Or in console: CloudWatch → Log Groups → /aws/events/<name>
```

### Key Log Groups

| Log Group | Contents |
|-----------|----------|
| `/aws/events/<name>` | Events matched by EventBridge rule |
| `/aws/lambda/<name>-processor` | Lambda function logs (if enabled) |

### Common Debugging Commands

```bash
# Check what's in the queue
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw queue_url) \
  --attribute-names ApproximateNumberOfMessages

# Peek at DLQ messages
aws sqs receive-message \
  --queue-url $(terraform output -raw dlq_url) \
  --max-number-of-messages 10

# Check Lambda logs
aws logs tail "/aws/lambda/$(terraform output -raw lambda_function_name)"
```

## Retry Logic

Events that fail processing follow this flow:

1. **Initial delivery** → Main SQS queue
2. **Processing failure** → Message returned to queue (visibility timeout expires)
3. **Retry** → Delivered again (up to `max_receive_count` times)
4. **Exhausted retries** → Moved to DLQ
5. **Alarm triggered** → SNS notification when DLQ has messages

Configure `sqs_visibility_timeout_seconds` to be at least 6x your Lambda timeout to allow for retry backoffs.

## Requirements

| Provider | Version |
|----------|---------|
| aws | ~> 5.0 |

## Opinionated defaults

- **DLQ enabled** by default (reliability first)
- **3 retries** before DLQ (configurable)
- **Alarms enabled** by default (monitoring first)
- **Least-privilege IAM** — Lambda can only access its SQS queue
- **Lambda timeout** must be less than SQS visibility timeout
- **EventBridge → SQS** — Decouples producer from processor

## Examples

- [`examples/basic`](examples/basic/) — Minimal EventBridge → SQS
- [`examples/complete`](examples/complete/) — Full pipeline with Lambda + alarms

## License

MIT
