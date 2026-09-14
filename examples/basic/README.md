# Event pipeline basic

EventBridge to SQS only. Events are queued for later processing.

## What it creates

- An EventBridge rule on the default bus matching `myapp.orders` events.
- An SQS queue with a DLQ and a max receive count of 3.
- No Lambda and no alarms.

## Before you start

- AWS credentials. Region defaults to `us-east-1`, environment to `dev`.
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
