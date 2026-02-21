# Getting Started with Event Pipeline

This guide walks you through using the Event Pipeline module for the first time.

## What This Module Does (In Plain English)

You have an application. Something happens (user signs up, order placed, etc.). You want to:
1. **React to that event** (send email, update database, notify another service)
2. **Not slow down your app** (do it asynchronously)
3. **Not lose events** (if your code crashes, retry)
4. **Know when things break** (get alerted)

This module wires together AWS services to do exactly that.

## The Pattern: EventBridge → SQS → Lambda

This is a well-established AWS pattern for event-driven architectures:

```
Your App ──► EventBridge ──► SQS Queue ──► Lambda ──► Your Business Logic
                │
                └──► CloudWatch Logs (for debugging)
```

**Why this combination?**
- **EventBridge**: Routes events based on patterns (like a smart router)
- **SQS**: Buffers events durably (survives crashes, handles spikes)
- **Lambda**: Scales to zero, scales up automatically

### AWS Documentation

- [EventBridge Tutorial: Send events to SQS](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-tutorial-sqs-logs.html)
- [SQS as an EventBridge Target](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-targets.html#eb-sqs)
- [Lambda Event Source Mapping for SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [AWS Whitepaper: Event-Driven Architecture](https://docs.aws.amazon.com/whitepapers/latest/serverless-event-driven-architectures/introduction.html)

---

## Step-by-Step: First Event Pipeline

### Step 1: Choose Your Event Pattern

What event do you want to react to? Examples:

| Use Case | Source | Detail Type |
|----------|--------|-------------|
| Welcome email | `myapp.auth` | `User Signed Up` |
| Process payment | `myapp.orders` | `Order Placed` |
| Audit logging | `myapp.api` | `Admin Action` |
| Data sync | `myapp.crm` | `Contact Updated` |

### Step 2: Create Your Lambda Function

Your Lambda receives events from SQS. Here's a minimal example:

**`index.js`**:
```javascript
exports.handler = async (event) => {
  console.log('Received events:', JSON.stringify(event, null, 2));
  
  for (const record of event.Records) {
    // Parse the EventBridge event from SQS message body
    const ebEvent = JSON.parse(record.body);
    console.log('EventBridge event:', ebEvent);
    
    // Your business logic here
    const { detail } = ebEvent;
    console.log('Processing:', detail);
    
    // Example: Send welcome email
    await sendWelcomeEmail(detail.userEmail);
  }
  
  return { statusCode: 200 };
};

async function sendWelcomeEmail(email) {
  // Your email sending logic
  console.log(`Sending welcome email to ${email}`);
}
```

**Package it**:
```bash
zip function.zip index.js
```

### Step 3: Deploy the Pipeline

**`main.tf`**:
```hcl
module "welcome_emails" {
  source  = "pomo-studio/event-pipeline/aws"
  version = "~> 1.0"

  name = "prod-welcome-emails"
  
  # Match user signup events
  event_pattern = {
    source      = ["myapp.auth"]
    detail-type = ["User Signed Up"]
  }
  
  # Process with Lambda
  create_lambda    = true
  lambda_code      = "${path.module}/function.zip"
  lambda_handler   = "index.handler"
  lambda_runtime   = "nodejs20.x"
  lambda_timeout   = 30
  
  # Enable logging and monitoring
  enable_logging = true
  enable_dlq     = true
  enable_alarms  = true
  alarm_email    = "your-email@example.com"
}
```

**Deploy**:
```bash
terraform init
terraform apply
```

### Step 4: Send a Test Event

From your application (or AWS CLI for testing):

```bash
aws events put-events --entries '[{
  "Source": "myapp.auth",
  "DetailType": "User Signed Up",
  "Detail": "{\"userId\":\"123\",\"userEmail\":\"test@example.com\",\"timestamp\":\"2026-02-21T12:00:00Z\"}"
}]'
```

### Step 5: Verify It Worked

**Check logs**:
```bash
# See the event in EventBridge logs
aws logs tail /aws/events/prod-welcome-emails --since 5m

# See Lambda processing
aws logs tail /aws/lambda/prod-welcome-emails-processor --since 5m
```

**Check SQS queue depth**:
```bash
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw queue_url) \
  --attribute-names ApproximateNumberOfMessages
```

---

## Understanding the Event Format

When your Lambda receives an event from SQS, the structure is:

```json
{
  "Records": [
    {
      "messageId": "abc-123",
      "body": {
        "version": "0",
        "id": "event-uuid",
        "detail-type": "User Signed Up",
        "source": "myapp.auth",
        "account": "123456789012",
        "time": "2026-02-21T12:00:00Z",
        "region": "us-east-1",
        "detail": {
          "userId": "123",
          "userEmail": "test@example.com"
        }
      }
    }
  ]
}
```

**Key fields**:
- `body.source`: Who sent the event
- `body.detail-type`: What kind of event
- `body.detail`: Your custom data
- `body.time`: When it happened

---

## Common Next Steps

### Adding More Event Types

You can match multiple event types with one pipeline:

```hcl
event_pattern = {
  source      = ["myapp.auth"]
  detail-type = ["User Signed Up", "User Upgraded", "User Cancelled"]
}
```

Or use content-based filtering:

```hcl
event_pattern = {
  source = ["myapp.orders"]
  detail = {
    status = ["completed"]
    amount = { numeric = [">=", 100] }
  }
}
```

### Handling Failures

If your Lambda throws an error:
1. Message returns to queue (visibility timeout expires)
2. Lambda retries (up to `max_receive_count` times, default 3)
3. After all retries fail → message goes to DLQ
4. You get an email alert (if `enable_alarms = true`)

**To reprocess DLQ messages**:
```bash
# Move messages from DLQ back to main queue
aws sqs start-message-move-task \
  --source-arn $(terraform output -raw dlq_arn) \
  --destination-arn $(terraform output -raw queue_arn)
```

### Monitoring in Production

Watch these CloudWatch metrics:

| Metric | Alarm When | Meaning |
|--------|------------|---------|
| `ApproximateNumberOfMessagesVisible` (DLQ) | > 0 | Events failing repeatedly |
| `Errors` (Lambda) | > 0 | Lambda code throwing exceptions |
| `Throttles` (Lambda) | > 0 | Lambda can't keep up with event rate |
| `ApproximateAgeOfOldestMessage` (Queue) | > 60s | Processing is falling behind |

---

## Troubleshooting

**"Events aren't reaching my Lambda"**
1. Check EventBridge logs: `aws logs tail /aws/events/<name>`
2. Verify event pattern matches what you're sending
3. Check SQS queue has messages: `aws sqs get-queue-attributes`

**"Lambda is failing but no DLQ alert"**
1. Check `enable_dlq = true` and `enable_alarms = true`
2. Verify `alarm_email` is set
3. Check SNS subscription is confirmed (check your email)

**"Events are in DLQ but I don't know why"**
1. Check Lambda logs: `aws logs tail /aws/lambda/<name>-processor`
2. Look for error messages or timeouts
3. Ensure Lambda timeout < SQS visibility timeout

---

## Further Reading

- [AWS EventBridge Patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
- [SQS Best Practices](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-best-practices.html)
- [Lambda Retry Behavior](https://docs.aws.amazon.com/lambda/latest/dg/invocation-retries.html)
- [Serverless Land: Event-Driven Patterns](https://serverlessland.com/patterns)
