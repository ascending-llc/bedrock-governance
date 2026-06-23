# Bedrock Governance

This repository contains a Terraform implementation for Amazon Bedrock governance

## Features

1. Application Inference Profile (AIP) provisioning
2. CloudTrail audit logging with encrypted S3 storage and 30-day rolling retention
3. CloudWatch anomaly alarms for input and output token usage per AIP
4. Organizations Service Control Policy that allows Bedrock invocation only through child-account AIPs

## Repository layout

```text
.
|- main.tf                      # Root orchestration entrypoint
|- backend.tf                   # Backend block (values sourced from backend config files)
|- bootstrap/
|  |- management_bootstrap.yaml # Management bootstrap (state backend)
|  |- child_bootstrap.yaml      # Child bootstrap (child deploy role)
|- deployment_accounts/
|  |- sandbox/
|  |  |- management_backend.hcl # Backend settings for management state
|  |  |- child_backend.hcl      # Backend settings for child state
|  |  |- management.tfvars      # Vars for management deployment
|  |  |- child.tfvars           # Vars for child deployment
|- modules/
|  |- bedrock_governance/      # Bedrock Governance Module
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
  --stack-name bedrock-governance-child-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    RoleName=BedrockGovernanceDeployer \
    TrustedPrincipalArn='<MANAGEMENT_IAM_ROLE_ARN>'
  ```

3. Copy bootstrap outputs into config files.

- Copy state bucket/table values from management bootstrap into both backend files:
  - `deployment_accounts/sandbox/management_backend.hcl`
  - `deployment_accounts/sandbox/child_backend.hcl`
- Copy `ChildDeployRoleArn` into `deployment_accounts/sandbox/child.tfvars` as `deploy_role_arn`.

4. Initialize Terraform for management state.

  ```bash
  terraform init -reconfigure -backend-config=deployment_accounts/sandbox/management_backend.hcl
  ```

5. Deploy management resources (SCP stack) in the management account.

  ```bash
  terraform plan -var-file=deployment_accounts/sandbox/management.tfvars
  terraform apply -var-file=deployment_accounts/sandbox/management.tfvars
  ```

6. Reinitialize Terraform for child state.

   ```bash
   terraform init -reconfigure -backend-config=deployment_accounts/sandbox/child_backend.hcl
   ```

7. Deploy child resources (AIPs, CloudTrail, alarms).

   ```bash
   terraform plan -var-file=deployment_accounts/sandbox/child.tfvars
   terraform apply -var-file=deployment_accounts/sandbox/child.tfvars
   ```
