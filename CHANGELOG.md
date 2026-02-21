# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/pomo-studio/terraform-aws-event-pipeline/releases/tag/v1.0.0
