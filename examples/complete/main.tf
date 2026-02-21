# Complete Example: Full Event Pipeline
# EventBridge → SQS → Lambda + DLQ + CloudWatch Alarms

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

# Create a simple Lambda function code
# In production, you'd have a proper build process
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/function.zip"

  source {
    content  = <<-EOF
      exports.handler = async (event) => {
        console.log('Received event:', JSON.stringify(event, null, 2));
        
        for (const record of event.Records) {
          const body = JSON.parse(record.body);
          console.log('Processing message:', body);
          
          // Simulate some processing
          await new Promise(resolve => setTimeout(resolve, 100));
          
          // Simulate occasional failures for testing
          if (Math.random() < 0.1) {
            throw new Error('Simulated processing error');
          }
        }
        
        return { statusCode: 200, body: 'Processed successfully' };
      };
    EOF
    filename = "index.js"
  }
}

module "event_pipeline" {
  source = "../.."
  # In production use:
  # source  = "pomo-studio/event-pipeline/aws"
  # version = "~> 1.0"

  name = "${var.environment}-payment-events"

  # Create custom event bus for isolation
  create_event_bus = true

  # Match payment events with specific status
  event_pattern = {
    source      = ["myapp.payments"]
    detail-type = ["Payment Processed"]
    detail = {
      status = ["completed", "failed", "refunded"]
      amount = {
        # Only process payments over $100
        numeric = [">", 100]
      }
    }
  }

  # Create Lambda processor
  create_lambda = true
  lambda_code   = data.archive_file.lambda.output_path
  lambda_handler = "index.handler"
  lambda_runtime = "nodejs20.x"
  lambda_timeout = 30
  lambda_memory_size = 256

  lambda_environment_variables = {
    LOG_LEVEL = "info"
    NODE_ENV  = var.environment
  }

  # SQS configuration
  sqs_visibility_timeout_seconds = 180  # 6x Lambda timeout
  sqs_message_retention_seconds  = 86400  # 1 day

  # Enable DLQ with 3 retries
  enable_dlq        = true
  max_receive_count = 3

  # Enable CloudWatch alarms
  enable_alarms = true
  alarm_email   = var.alarm_email

  dlq_alarm_threshold     = 1
  lambda_error_threshold  = 1

  tags = {
    Environment = var.environment
    Project     = "event-pipeline-complete"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}
