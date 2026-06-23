# Bedrock Governance

This repository contains a Terraform implementation for Amazon Bedrock governance

## Features

1. Application Inference Profile (AIP) provisioning
2. CloudTrail audit logging with encrypted S3 storage and 30-day rolling retention
3. CloudWatch anomaly alarms for input and output token usage per AIP
4. Service Control Policy that allows Bedrock invocation only through child-account AIPs

## Repository layout

```text
|- main.tf                      # Root orchestration entrypoint
|- backend.tf                   # Backend block (values sourced from backend config files)
|- bootstrap/
|  |- management_bootstrap.yaml # Management bootstrap (Terraform state backend)
|  |- child_bootstrap.yaml      # Child bootstrap (Terraform deploy role)
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
    --stack-name bedrock-governance-management-bootstrap \
    --region us-east-1 \
    --parameter-overrides \
      BucketNamePrefix=asc-bedrock-governance-<ACCOUNT_ID>-us-east-1 \
      LockTableName=terraform-locks-<ACCOUNT_ID>-us-east-1
  ```

2. Bootstrap each child account once (child deploy role).

  ```bash
  aws cloudformation deploy \
    --template-file bootstrap/child_bootstrap.yaml \
    --stack-name bedrock-governance-child-bootstrap \
    --region us-east-1 \
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

> **Important:** Always run `terraform init -reconfigure` with the correct backend file before each management/child plan or apply. This prevents cross-mode state collisions.

7. Deploy child resources (AIPs, CloudTrail, alarms).

  ```bash
  terraform plan -var-file=deployment_accounts/sandbox/child.tfvars
  terraform apply -var-file=deployment_accounts/sandbox/child.tfvars
  ```

## Claude Code integration

Use this after Terraform deployment is complete (SCP + child AIPs are deployed).

### Prerequisites

1. Claude Code **v2.1.94+** (latest recommended).
2. AWS credentials that can invoke Bedrock in the target account.
3. Deployed application inference profile (AIP) ARNs.

### Setup

1. In Claude Code, run:

```text
/setup-bedrock
```

2. Choose Amazon Bedrock and set region/account credentials.
3. Run `/status` and confirm provider is Bedrock.

### Pin models to AIPs in `~/.claude/settings.json`

```json
{
  "modelOverrides": {
    "claude-sonnet-4-6": "arn:aws:bedrock:us-east-1:766796016661:application-inference-profile/<sonnet-aip-id>",
    "claude-haiku-4-5": "arn:aws:bedrock:us-east-1:766796016661:application-inference-profile/<haiku-aip-id>"
  }
}
```

If you prefer env-var pinning, set `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_*_MODEL` to AIP ARNs.

### Validate governance behavior

1. Invoke through Claude Code and confirm requests succeed with pinned AIPs.
2. Attempt direct foundation-model invocation (outside AIP) and verify SCP deny.
