# Architecture: EventBridge + SQS + Lambda

This document explains the architectural pattern implemented by this module, including design decisions and AWS best practices.

## Module boundary

Before diving into the architecture, it helps to understand exactly what this
module owns versus what you own.

```
Your code / AWS service
        │
        │  events:PutEvents  (YOUR code, YOUR IAM)
        ▼
┌─────────────────────────────────────────────────────────────┐
│               EventBridge Event Bus                         │
│  (default bus auto-exists in every account; or create a     │
│   custom one with create_event_bus = true — module creates  │
│   the bus but you still PutEvents onto it)                  │
└────────────────────────┬────────────────────────────────────┘
                         │
          ┌──────────────▼──────────────────────────────────┐
          │         THIS MODULE MANAGES                      │
          │                                                   │
          │  EventBridge Rule (pattern filter)               │
          │          │                                        │
          │          ▼                                        │
          │  SQS Queue  ──►  DLQ (on failure)               │
          │          │                                        │
          │          ▼                                        │
          │  Lambda Function  (you provide the code/zip)     │
          │  Lambda IAM Role  (module creates, least-priv)   │
          │  CloudWatch Alarms + SNS                         │
          └─────────────────────────────────────────────────-┘
                         │
          ┌──────────────▼──────────────────────────────────┐
          │         YOUR RESPONSIBILITY (post-module)        │
          │                                                   │
          │  • Business logic inside the Lambda handler      │
          │  • Updating the Lambda zip when code changes     │
          │  • DLQ drain strategy (reprocess / discard)      │
          │  • Any downstream systems Lambda writes to       │
          └─────────────────────────────────────────────────-┘
```

**Key boundary rule**: The module manages the *infrastructure wiring*. You own
the event source (what puts events on the bus) and the event sink (what your
Lambda actually does with the event).

## The Pattern

This module implements the **"Event Router + Queue + Consumer"** pattern, which is AWS's recommended approach for reliable event processing.

```
┌─────────────┐     ┌──────────────┐     ┌───────────┐     ┌──────────┐
│   Source    │────►│  EventBridge │────►│    SQS    │────►│  Lambda  │
│  (Your App) │     │   (Router)   │     │  (Queue)  │     │(Consumer)│
└─────────────┘     └──────────────┘     └───────────┘     └──────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │CloudWatch Logs│
                     │ (Debugging)  │
                     └──────────────┘
```

## Why This Combination?

### EventBridge (Event Router)

**Purpose**: Decouple event producers from consumers

**Key capabilities**:
- Pattern matching (route based on event content)
- Multiple targets from single rule
- Schema validation
- Event replay (archive and replay events)

**AWS Docs**: [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)

### SQS (Queue)

**Purpose**: Buffer and durably store events

**Key capabilities**:
- Durability (events survive crashes)
- Decoupling (consumer can be down)
- Batching (process multiple events efficiently)
- Backpressure (queue depth indicates load)

**Why SQS over direct Lambda invocation?**

| Feature | Direct Lambda | SQS + Lambda |
|---------|---------------|--------------|
| Durability | ❌ Event lost if Lambda fails | ✅ Event stays in queue |
| Retry | ❌ Sync failure handling | ✅ Automatic with DLQ |
| Batching | ❌ One event per invocation | ✅ Up to 10,000 per poll |
| Rate limiting | ❌ Can overwhelm Lambda | ✅ SQS buffers spikes |
| Cost | Higher (more invocations) | Lower (batching) |

**AWS Docs**: [SQS Developer Guide](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html)

### Lambda (Consumer)

**Purpose**: Event processing logic

**Key capabilities**:
- Auto-scaling (from 0 to thousands of concurrent executions)
- Pay-per-use (only pay when processing)
- Built-in retry and DLQ integration

**AWS Docs**: [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)

## Design Decisions

### 1. SQS as Target (Not Direct Lambda)

EventBridge can invoke Lambda directly. Why add SQS?

**Direct Lambda invocation**:
- Event triggers Lambda immediately
- If Lambda fails, EventBridge retries (24 hours, exponential backoff)
- No built-in DLQ
- No batching

**SQS in the middle**:
- Event buffered in queue
- Lambda polls at its own pace
- Built-in DLQ with configurable retry count
- Batch processing (up to 10,000 messages)
- Queue depth visibility

**When to use direct Lambda**: Low-volume, must-process-immediately scenarios
**When to use SQS**: Most production workloads (reliability + cost)

**AWS Reference**: [EventBridge Targets - SQS](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-targets.html#eb-sqs)

### 2. Dead Letter Queue (DLQ)

After `max_receive_count` failed processing attempts, messages go to DLQ.

**Why this matters**:
- Poison messages don't block the queue
- You can inspect and reprocess failed events
- Alerts tell you when manual intervention needed

**AWS Best Practice**: [SQS DLQ](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)

### 3. Visibility Timeout = 6x Lambda Timeout

SQS visibility timeout determines how long a message is invisible to other consumers after being received.

**If Lambda timeout (30s) > Visibility timeout (30s)**:
- Lambda still processing
- Message becomes visible again
- Another Lambda picks it up
- **Same event processed twice!**

**Our default**: 180s visibility, 30s Lambda timeout = safe 6x buffer

**AWS Docs**: [SQS Visibility Timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)

### 4. EventBridge Logging

Every matched event is logged to CloudWatch.

**Why**: Debugging event patterns. Without logs, you can't tell:
- Did my event reach EventBridge?
- Did the pattern match?
- What did the event look like?

**AWS Docs**: [EventBridge Logging](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-logging-event-patterns.html)

## Alternative Patterns

### Pattern: SNS Instead of SQS

```
EventBridge → SNS → Multiple Lambdas (fan-out)
```

**When to use**: One event needs to trigger multiple independent actions
**Trade-off**: No message buffering, harder to monitor

### Pattern: Kinesis Instead of SQS

```
EventBridge → Kinesis → Lambda (stream processing)
```

**When to use**: Very high throughput (thousands TPS), need ordering guarantees
**Trade-off**: More complex, more expensive

### Pattern: Step Functions Instead of Lambda

```
EventBridge → SQS → Step Functions (orchestration)
```

**When to use**: Multi-step workflows with error handling, retries, parallel steps
**Trade-off**: More expensive, higher latency

## Cost Considerations

Approximate costs per 1M events:

| Component | Cost |
|-----------|------|
| EventBridge | $1.00 |
| SQS (standard) | $0.40 |
| Lambda (128MB, 1s avg) | $2.08 |
| CloudWatch Logs | ~$0.50 |
| **Total** | **~$4/M events** |

**Cost optimization tips**:
- Use batching (process multiple events per Lambda invocation)
- Adjust log retention (default: 14 days)
- Consider SQS FIFO only if you need ordering

## Security Best Practices

Implemented in this module:

1. **Least-privilege IAM**: Lambda can only access its specific SQS queue
2. **Encryption at rest**: SQS uses AWS-managed KMS by default
3. **Encryption in transit**: All service communication over TLS
4. **No hardcoded secrets**: Use Lambda environment variables + Secrets Manager

**AWS Security Guide**: [Lambda Security](https://docs.aws.amazon.com/lambda/latest/dg/security.html)

## Monitoring Strategy

### Key Metrics to Watch

| Metric | Service | Critical Threshold |
|--------|---------|-------------------|
| `ApproximateNumberOfMessagesVisible` | SQS Main | < 1000 (backlog) |
| `ApproximateNumberOfMessagesVisible` | SQS DLQ | = 0 (any messages = failures) |
| `ApproximateAgeOfOldestMessage` | SQS | < 60 seconds |
| `Errors` | Lambda | = 0 |
| `Throttles` | Lambda | = 0 |
| `Duration` | Lambda | < Timeout (ideally < 50% of timeout) |

### Dashboard Queries

CloudWatch Insights query for event latency:
```sql
fields @timestamp, @message
| filter @message like /Processing/
| stats avg(@timestamp - detail.time) as avg_latency by bin(5m)
```

## Real-World Case Studies

### Netflix
Uses EventBridge + SQS for video encoding pipeline. Events trigger when uploads complete, SQS buffers during encoding spikes.

### Airbnb
Uses similar pattern for booking confirmation emails. EventBridge routes by booking type, SQS ensures no emails lost during traffic spikes.

### AWS's Own Services
Many AWS services use this pattern internally. It's the backbone of serverless event processing.

## Further Reading

### AWS Documentation
- [EventBridge Best Practices](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-best-practices.html)
- [SQS Best Practices](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-best-practices.html)
- [Lambda Event Source Mapping](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html)

### AWS Blog Posts
- [Building event-driven architectures with EventBridge](https://aws.amazon.com/blogs/compute/building-event-driven-architectures-with-amazon-eventbridge/)
- [Serverless event-driven architecture with EventBridge](https://aws.amazon.com/blogs/compute/serverless-event-driven-architecture-with-amazon-eventbridge/)
- [Understanding the Different Ways to Invoke Lambda Functions](https://aws.amazon.com/blogs/architecture/understanding-the-different-ways-to-invoke-lambda-functions/)

### AWS Whitepapers
- [Serverless Event-Driven Architectures](https://docs.aws.amazon.com/whitepapers/latest/serverless-event-driven-architectures/introduction.html)
- [Event-Driven Architecture on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-event-driven-architecture/introduction.html)

### Reference Architectures
- [AWS Serverless Application Repository Patterns](https://serverlessland.com/patterns)
- [EventBridge Scheduler Patterns](https://serverlessland.com/patterns/eventbridge-sqs)
