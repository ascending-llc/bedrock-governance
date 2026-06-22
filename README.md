# Bedrock Governance

This repository contains a Terraform implementation for Amazon Bedrock governance with support for account-specific deployment variance.

## Features

1. Application Inference Profile (AIP) provisioning from `model_sources` model IDs
2. CloudTrail audit logging with encrypted S3 storage
3. CloudWatch anomaly alarms for input and output token usage per AIP
4. Organizations Service Control Policy that allows Bedrock invocation only through child-account AIPs
5. Multi-account deployment overlays using per-account backend and tfvars files

## Key inputs

- `model_sources` (child mode): list of model IDs used to create AIPs.
  - If `model_id` starts with `us.`, `eu.`, `apac.`, `global.`, or `us-gov.`, it is treated as a cross-region inference profile ID.
  - Otherwise, it is treated as a foundation model ID.
  - CloudWatch anomaly alarms are always created per AIP (input and output token count).
  - Per-model tags are not supported; governance resources are tagged with `aws-apn-id` from `apn_id`.
- `scp_target_ids` (management mode): list of Organizations account IDs and/or OU IDs for SCP attachment.
  - When account IDs are present, SCP conditions are scoped to those child-account AIP ARNs.

## Repository layout

```text
.
|- main.tf                      # Root orchestration entrypoint
|- backend.tf                   # Backend block (values sourced from backend.hcl)
|- backend.hcl.example          # Backend config example
|- bootstrap/
|  |- s3_dynamodb.yaml          # State bucket + lock table bootstrap
|- deployment_accounts/
|  |- example/
|  |  |- backend.hcl            # Account-specific backend settings
|  |  |- management.tfvars      # Vars for management deployment
|  |  |- child.tfvars           # Vars for child deployment
|- modules/
|  |- bedrock_governance/.      # Re-usable Bedrock Governance Stack
```

## Prerequisites

1. Terraform 1.5+
2. AWS CLI configured for target accounts

## Bootstrap remote state

Deploy bootstrap/s3_dynamodb.yaml once in the state-hosting account:

```bash
aws cloudformation deploy \
  --template-file bootstrap/s3_dynamodb.yaml \
  --stack-name terraform-state \
  --parameter-overrides BucketNamePrefix=bedrock-governance
```

Then update each deployment_accounts/<account>/backend.hcl with the correct bucket and key.

Recommended state account: management account.

Why:

1. Centralized governance and auditability for all Terraform states.
2. Better separation of duties (child accounts consume infrastructure, but do not own shared state control).
3. Reduced blast radius if a child account is changed, suspended, or decommissioned.
4. Simpler IAM policy management for state bucket and lock table.

## Deployment instructions

1. Deploy the remote state bootstrap stack (once, in the state-hosting account):

   ```bash
   aws cloudformation deploy \
     --template-file bootstrap/s3_dynamodb.yaml \
     --stack-name terraform-state \
     --parameter-overrides BucketNamePrefix=bedrock-governance
   ```

2. Update each `deployment_accounts/<account>/backend.hcl` with the real S3 bucket, key, region, and DynamoDB table values created by the bootstrap stack.

3. Initialize Terraform for the target account:

  ```bash
  terraform init -reconfigure -backend-config=deployment_accounts/example/backend.hcl
  ```

4. Deploy management account resources:

  ```bash
  terraform plan -var-file=deployment_accounts/example/management.tfvars
  terraform apply -var-file=deployment_accounts/example/management.tfvars
  ```

5. Deploy child account resources:

  ```bash
  terraform plan -var-file=deployment_accounts/example/child.tfvars
  terraform apply -var-file=deployment_accounts/example/child.tfvars
  ```
