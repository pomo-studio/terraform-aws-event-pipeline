.PHONY: test test-setup fmt validate

## Run all unit tests (generates fixtures first)
test: test-setup
	terraform test

## Generate test fixture zip required by Lambda tests
test-setup:
	cd tests/fixtures && zip -q function.zip index.js

## Check Terraform formatting
fmt:
	terraform fmt -check -recursive

## Validate all examples
validate:
	cd examples/basic && terraform init -backend=false -upgrade && terraform validate
	cd examples/complete && terraform init -backend=false -upgrade && terraform validate
