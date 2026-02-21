# Basic Example: EventBridge → SQS only
# No Lambda, no alarms - just reliable event queuing

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "event_pipeline" {
  source = "../.."
  # In production use:
  # source  = "pomo-studio/event-pipeline/aws"
  # version = "~> 1.0"

  name = "${var.environment}-order-events"

  # Match events from your application
  event_pattern = {
    source      = ["myapp.orders"]
    detail-type = ["Order Placed", "Order Updated", "Order Cancelled"]
  }

  # Use default event bus (no custom bus created)
  create_event_bus = false

  # No Lambda - just queue events for later processing
  create_lambda = false

  # Enable DLQ for reliability
  enable_dlq        = true
  max_receive_count = 3

  # No alarms for this simple example
  enable_alarms = false

  tags = {
    Environment = var.environment
    Project     = "event-pipeline-demo"
    ManagedBy   = "terraform"
  }
}
