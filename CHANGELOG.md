# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-02-21

### Fixed
- `aws_cloudwatch_event_target.logs` was missing `event_bus_name`, causing it to
  target the default event bus instead of the custom bus. When `create_event_bus=true`,
  the CloudWatch Logs target now correctly references the custom bus.

## [1.1.0] - 2026-02-21

### Added
- Native `terraform test` suite with 16 test runs covering resource creation,
  conditional toggles, naming conventions, IAM policy content, and all
  variable validation rules — no AWS credentials required (mock_provider)
- `Makefile` with `test`, `fmt`, and `validate` targets

### Changed
- **Minimum Terraform version bumped to >= 1.9.0** (from 1.5.0) to support
  cross-variable references in validation blocks
- `source_code_hash` on Lambda function now guards against null `lambda_code`
  to avoid eager evaluation errors during validation tests

### Fixed
- `function_response_types = ["ReportBatchItemFailures"]` added to SQS event
  source mapping — without this, a single failed message caused the entire
  batch to retry instead of only the failed message returning to the queue
- `sqs:ChangeMessageVisibilityBatch` added to Lambda IAM policy — required
  companion permission for partial batch failure reporting
- EventBridge logging target (`aws_cloudwatch_event_target`) was created but
  never connected to the rule; log group and IAM role now wired correctly
- `var.log_level` removed (was defined, validated, and applied nowhere)
- `source_code_hash` added to Lambda function so code changes trigger redeploy
- Cross-variable validation enforces `lambda_timeout < sqs_visibility_timeout_seconds`
- `lambda_batch_size` is now configurable (was hardcoded at 10)
- `dlq_visibility_timeout_seconds` is now configurable (was hardcoded at 30)

### Upgrading from 1.0.0

Terraform >= 1.9.0 is now required. If you are running an older version,
upgrade your Terraform binary before updating this module. No changes to
module inputs or outputs are required.

## [1.0.0] - 2026-02-21

### Added
- Initial release of Event Pipeline module
- EventBridge rule with pattern matching
- SQS queue with optional Dead Letter Queue
- Lambda event processor with event source mapping
- CloudWatch logging for EventBridge events
- CloudWatch alarms for DLQ depth and Lambda errors
- SNS topic for alarm notifications
- Comprehensive input validation
- Basic and Complete examples
- CI/CD pipelines for validation and releases

### Features
- **Reliable event processing**: SQS buffering with DLQ for failed events
- **Flexible deployment**: Optional Lambda, event bus, alarms
- **Production-ready**: Least-privilege IAM, logging, monitoring
- **Developer-friendly**: Validation prevents common mistakes

[1.1.0]: https://github.com/pomo-studio/terraform-aws-event-pipeline/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/pomo-studio/terraform-aws-event-pipeline/releases/tag/v1.0.0
