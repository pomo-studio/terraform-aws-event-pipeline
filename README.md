# terraform-aws-event-pipeline

[![Terraform Validation](https://github.com/pomo-studio/terraform-aws-event-pipeline/actions/workflows/terraform.yml/badge.svg)](https://github.com/pomo-studio/terraform-aws-event-pipeline/actions/workflows/terraform.yml)
[![Terraform Registry](https://img.shields.io/badge/terraform-registry-844FBA?logo=terraform)](https://registry.terraform.io/modules/pomo-studio/event-pipeline/aws)

- [Changelog](CHANGELOG.md)

## Deprecated

This module is deprecated and maintained for existing consumers only.

For new implementations, use:

- `pomo-studio/event-bus/aws` for shared EventBridge bus infrastructure
- `pomo-studio/event-consumer/aws` for per-service EventBridge -> SQS -> optional Lambda consumers

See [Migration](#migration) for a direct replacement example.

Terraform module for AWS event-driven pipelines: EventBridge → SQS → Lambda with optional DLQ, alarms, and CloudWatch logging.

- Full EventBridge → SQS → Lambda wiring in one module call: no queue policies or IAM to wire manually
- DLQ and retry logic on by default: failed events are preserved, never silently dropped
- CloudWatch alarms for DLQ depth, Lambda errors, and throttles included out of the box
- Least-privilege Lambda IAM role auto-generated and scoped to its own queue only
- Caller owns producers and business logic: module handles all the event routing plumbing

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

## Design decisions

**EventBridge → SQS over direct invocation**: decouples event producer from processor; SQS absorbs bursts and provides retry semantics independently of Lambda.

**DLQ on by default**: failed events are preserved rather than silently dropped. Drain strategy (reprocess, alert, discard) is the caller's responsibility.

**Alarms on by default**: DLQ depth ≥ 1 and Lambda errors ≥ 1 are treated as incidents. Both thresholds are configurable.

**`lambda_timeout` < `sqs_visibility_timeout_seconds` enforced**: validated at plan time to prevent duplicate processing from visibility timeout expiry during execution.

**Caller owns producers and IAM for them**: `events:PutEvents` permission on the bus is not managed here; the calling module grants it to whatever publishes events.

## Examples

- [`examples/basic`](examples/basic/): EventBridge → SQS only
- [`examples/complete`](examples/complete/): full pipeline with Lambda and alarms

## Reference

<details>
<summary>Reference</summary>

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0, < 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.64.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_bus.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus) | resource |
| [aws_cloudwatch_event_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_cloudwatch_metric_alarm.dlq_depth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.lambda_errors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.lambda_throttles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.lambda_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.lambda_basic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_event_source_mapping.sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_lambda_function.processor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.alarm_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_email"></a> [alarm\_email](#input\_alarm\_email) | Email address for alarm notifications (required if enable\_alarms=true) | `string` | `null` | no |
| <a name="input_create_event_bus"></a> [create\_event\_bus](#input\_create\_event\_bus) | Create a custom event bus. If false, uses the default event bus. | `bool` | `false` | no |
| <a name="input_create_lambda"></a> [create\_lambda](#input\_create\_lambda) | Create a Lambda function to process events from SQS | `bool` | `false` | no |
| <a name="input_dlq_alarm_threshold"></a> [dlq\_alarm\_threshold](#input\_dlq\_alarm\_threshold) | DLQ depth alarm threshold (messages in DLQ) | `number` | `1` | no |
| <a name="input_dlq_visibility_timeout_seconds"></a> [dlq\_visibility\_timeout\_seconds](#input\_dlq\_visibility\_timeout\_seconds) | DLQ visibility timeout in seconds (DLQ is for holding failed messages, not processing) | `number` | `30` | no |
| <a name="input_enable_alarms"></a> [enable\_alarms](#input\_enable\_alarms) | Enable CloudWatch alarms for monitoring | `bool` | `true` | no |
| <a name="input_enable_dlq"></a> [enable\_dlq](#input\_enable\_dlq) | Enable Dead Letter Queue for failed events | `bool` | `true` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable CloudWatch logging for EventBridge events | `bool` | `true` | no |
| <a name="input_event_pattern"></a> [event\_pattern](#input\_event\_pattern) | EventBridge event pattern as a map/object. See AWS docs for pattern syntax. | `any` | n/a | yes |
| <a name="input_lambda_batch_size"></a> [lambda\_batch\_size](#input\_lambda\_batch\_size) | Maximum number of records to read from SQS in one batch (1-10000) | `number` | `10` | no |
| <a name="input_lambda_code"></a> [lambda\_code](#input\_lambda\_code) | Path to Lambda deployment package zip file (required if create\_lambda=true) | `string` | `null` | no |
| <a name="input_lambda_environment_variables"></a> [lambda\_environment\_variables](#input\_lambda\_environment\_variables) | Environment variables for Lambda function | `map(string)` | `{}` | no |
| <a name="input_lambda_error_threshold"></a> [lambda\_error\_threshold](#input\_lambda\_error\_threshold) | Lambda error rate alarm threshold (errors per minute) | `number` | `1` | no |
| <a name="input_lambda_handler"></a> [lambda\_handler](#input\_lambda\_handler) | Lambda function handler (e.g., 'index.handler') | `string` | `"index.handler"` | no |
| <a name="input_lambda_memory_size"></a> [lambda\_memory\_size](#input\_lambda\_memory\_size) | Lambda memory size in MB | `number` | `128` | no |
| <a name="input_lambda_runtime"></a> [lambda\_runtime](#input\_lambda\_runtime) | Lambda runtime | `string` | `"nodejs20.x"` | no |
| <a name="input_lambda_timeout"></a> [lambda\_timeout](#input\_lambda\_timeout) | Lambda function timeout in seconds (must be less than SQS visibility timeout) | `number` | `30` | no |
| <a name="input_max_receive_count"></a> [max\_receive\_count](#input\_max\_receive\_count) | Max receives before sending to DLQ (1-1000) | `number` | `3` | no |
| <a name="input_name"></a> [name](#input\_name) | Resource naming prefix (e.g., 'prod-order-events') | `string` | n/a | yes |
| <a name="input_sqs_message_retention_seconds"></a> [sqs\_message\_retention\_seconds](#input\_sqs\_message\_retention\_seconds) | SQS message retention period in seconds | `number` | `345600` | no |
| <a name="input_sqs_visibility_timeout_seconds"></a> [sqs\_visibility\_timeout\_seconds](#input\_sqs\_visibility\_timeout\_seconds) | SQS visibility timeout in seconds (should be 6x Lambda timeout) | `number` | `180` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_topic_arn"></a> [alarm\_topic\_arn](#output\_alarm\_topic\_arn) | ARN of the SNS topic for alarms (null if disabled) |
| <a name="output_dlq_alarm_name"></a> [dlq\_alarm\_name](#output\_dlq\_alarm\_name) | Name of the DLQ depth alarm (null if disabled) |
| <a name="output_dlq_arn"></a> [dlq\_arn](#output\_dlq\_arn) | ARN of the Dead Letter Queue (null if disabled) |
| <a name="output_dlq_name"></a> [dlq\_name](#output\_dlq\_name) | Name of the Dead Letter Queue (null if disabled) |
| <a name="output_dlq_url"></a> [dlq\_url](#output\_dlq\_url) | URL of the Dead Letter Queue (null if disabled) |
| <a name="output_event_bus_arn"></a> [event\_bus\_arn](#output\_event\_bus\_arn) | ARN of the EventBridge event bus |
| <a name="output_event_bus_name"></a> [event\_bus\_name](#output\_event\_bus\_name) | Name of the EventBridge event bus (or 'default') |
| <a name="output_event_rule_arn"></a> [event\_rule\_arn](#output\_event\_rule\_arn) | ARN of the EventBridge rule |
| <a name="output_event_rule_name"></a> [event\_rule\_name](#output\_event\_rule\_name) | Name of the EventBridge rule |
| <a name="output_lambda_error_alarm_name"></a> [lambda\_error\_alarm\_name](#output\_lambda\_error\_alarm\_name) | Name of the Lambda error alarm (null if disabled) |
| <a name="output_lambda_function_arn"></a> [lambda\_function\_arn](#output\_lambda\_function\_arn) | ARN of the Lambda function (null if disabled) |
| <a name="output_lambda_function_name"></a> [lambda\_function\_name](#output\_lambda\_function\_name) | Name of the Lambda function (null if disabled) |
| <a name="output_lambda_role_arn"></a> [lambda\_role\_arn](#output\_lambda\_role\_arn) | ARN of the Lambda IAM role (null if disabled) |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | CloudWatch log group ARN for EventBridge events (null if logging disabled) |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch log group for EventBridge events (null if logging disabled) |
| <a name="output_queue_arn"></a> [queue\_arn](#output\_queue\_arn) | ARN of the main SQS queue |
| <a name="output_queue_name"></a> [queue\_name](#output\_queue\_name) | Name of the main SQS queue |
| <a name="output_queue_url"></a> [queue\_url](#output\_queue\_url) | URL of the main SQS queue |
<!-- END_TF_DOCS -->

</details>

## License

MIT
