# Event pipeline complete

Full pipeline: custom event bus to SQS to Lambda, with DLQ and alarms.

## What it creates

- A custom EventBridge bus and a rule matching payment events over $100.
- An SQS queue with a 180s visibility timeout, 1-day retention, and a DLQ.
- A `nodejs20.x` Lambda processor packaged from inline code at apply time.
- CloudWatch alarms that email the address in `alarm_email`.

## Before you start

- AWS credentials. Region defaults to `us-east-1`, environment to `dev`.
- Set `alarm_email`, it has no default.
- Uses the module from the local path `../..`, not the registry.

## Run it

```bash
terraform init
terraform plan
terraform apply
```

## Clean up

```bash
terraform destroy
```
