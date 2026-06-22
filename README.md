# Bedrock Governance

This repository contains a Terraform implementation for Amazon Bedrock governance

## Features

1. Application Inference Profile (AIP) provisioning
2. CloudTrail audit logging with encrypted S3 storage
3. CloudWatch anomaly alarms for input and output token usage per AIP
4. Organizations Service Control Policy that allows Bedrock invocation only through child-account AIPs

## Repository layout

```text
.
|- main.tf                      # Root orchestration entrypoint
|- backend.tf                   # Backend block (values sourced from backend.hcl)
|- bootstrap/
|  |- management_bootstrap.yaml # Management bootstrap (state backend)
|  |- child_bootstrap.yaml      # Child bootstrap (child deploy role)
|- deployment_accounts/
|  |- example/
|  |  |- backend.hcl            # Account-specific backend settings
|  |  |- management.tfvars      # Vars for management deployment
|  |  |- child.tfvars           # Vars for child deployment
|- modules/
|  |- bedrock_governance/.      # Re-usable Bedrock Governance Module
```

## Prerequisites

1. Terraform 1.5+
2. AWS CLI configured for target accounts

## Deployment Instructions

1. Bootstrap the management account once (state backend).

  ```bash
  aws cloudformation deploy \
    --template-file bootstrap/management_bootstrap.yaml \
    --stack-name bedrock-governance-management-bootstrap
  ```

2. Bootstrap each child account once (child deploy role).

  ```bash
  aws cloudformation deploy \
    --template-file bootstrap/child_bootstrap.yaml \
    --stack-name bedrock-governance-child-bootstrap
  ```

3. Copy bootstrap outputs into config files.

- Copy state bucket/table values from management bootstrap into `deployment_accounts/example/backend.hcl`.
- Copy `ChildDeployRoleArn` into `deployment_accounts/example/child.tfvars` as `deploy_role_arn`.

4. Initialize Terraform using the backend config.

  ```bash
  terraform init -backend-config=deployment_accounts/example/backend.hcl
  ```

5. Deploy management resources (SCP stack) as `Ascending-administrator-role` in the management account.

  ```bash
  terraform plan -var-file=deployment_accounts/example/management.tfvars
  terraform apply -var-file=deployment_accounts/example/management.tfvars
  ```

6. Deploy child resources (AIPs, CloudTrail, alarms).

  ```bash
  terraform plan -var-file=deployment_accounts/example/child.tfvars
  terraform apply -var-file=deployment_accounts/example/child.tfvars
  ```
