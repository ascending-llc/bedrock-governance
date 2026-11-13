# Deployment Guide

## Prerequisites

1. Terraform 1.5+
2. AWS CLI configured with credentials for both the management account and each child account
3. AWS Organizations enabled on the management account

## Architecture overview

Deployment is split across two Terraform states:

- **Management state** — creates the Service Control Policy (SCP) and attaches it to target accounts/OUs. Runs with management-account credentials.
- **Child state** — creates Application Inference Profiles (AIPs), CloudTrail audit trail, and CloudWatch anomaly alarms. Runs by assuming a deploy role in the child account.

Both states use the same root module, distinguished by `deployment_mode = "management"` or `"child"` in the tfvars file.

## Step 1 — Bootstrap the management account (once)

Creates the S3 state bucket and DynamoDB lock table.

```bash
aws cloudformation deploy \
  --template-file bootstrap/management_bootstrap.yaml \
  --stack-name bedrock-governance-management-bootstrap \
  --region us-east-1 \
  --parameter-overrides \
    BucketNamePrefix=bedrock-governance-<ACCOUNT_ID>-us-east-1 \
    LockTableName=terraform-locks-<ACCOUNT_ID>-us-east-1
```

Note the `S3BucketName` and `DynamoDBTableName` values from the stack outputs — you will use them in Step 3.

## Step 2 — Bootstrap each child account (once per account)

Creates the `BedrockGovernanceDeployer` IAM role in the child account. Choose the approach that matches your scale.

### Single account

Run with child-account credentials.

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

Note the `ChildDeployRoleArn` value from the stack outputs — you will use it in Step 3.

### Organizational Unit (OU) — CloudFormation StackSets

For deployments across many accounts, use a SERVICE_MANAGED StackSet from the management account. This deploys `BedrockGovernanceDeployer` to every account in the OU in one operation, and automatically deploys to any account added to the OU in the future.

**Prerequisites:** AWS Organizations trusted access for CloudFormation must be enabled.

```bash
aws organizations enable-aws-service-access \
  --service-principal stacksets.amazonaws.com

aws cloudformation activate-trusted-access
```

**Create the StackSet:**

```bash
aws cloudformation create-stack-set \
  --stack-set-name bedrock-governance-child-bootstrap \
  --template-body file://bootstrap/child_bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --parameters \
    ParameterKey=TrustedPrincipalArn,ParameterValue='<MANAGEMENT_IAM_ROLE_ARN>' \
  --region us-east-1
```

**Deploy to the OU**
```bash
aws cloudformation create-stack-instances \
  --stack-set-name bedrock-governance-child-bootstrap \
  --deployment-targets OrganizationalUnitIds='["<OU_ID>"]' \
  --regions us-east-1 \
  --region us-east-1
```

After the operation completes, retrieve all deploy role ARNs:

```bash
aws cloudformation list-stack-instances \
  --stack-set-name bedrock-governance-child-bootstrap \
  --region us-east-1
```

Use the `ChildDeployRoleArn` output from each stack instance when populating `child.tfvars` per account.

## Step 3 — Populate config files

Copy the following values from the CloudFormation stack outputs into the config files in `deployment_accounts/example/` (or your copy of that folder).

| Output | File | Key |
|---|---|---|
| `S3BucketName` (management bootstrap) | `management_backend.hcl` | `bucket` |
| `DynamoDBTableName` (management bootstrap) | `management_backend.hcl` | `dynamodb_table` |
| `S3BucketName` (management bootstrap) | `child_backend.hcl` | `bucket` |
| `DynamoDBTableName` (management bootstrap) | `child_backend.hcl` | `dynamodb_table` |
| `ChildDeployRoleArn` (child bootstrap) | `child.tfvars` | `deploy_role_arn` |

## Step 4 — Deploy child resources

Reinitialize Terraform with the child backend, then apply.

```bash
terraform init -reconfigure -backend-config=deployment_accounts/example/child_backend.hcl
terraform plan  -var-file=deployment_accounts/example/child.tfvars
terraform apply -var-file=deployment_accounts/example/child.tfvars
```

This deploys AIPs, the CloudTrail trail, the audit S3 bucket, and CloudWatch anomaly alarms.
For a POC that requires alert delivery, set exactly one of `alarm_email` or
`alarm_sns_topic_arn` and set `require_alarm_notification = true`. Email targets
must confirm the SNS subscription before delivery works; a test asserts alarms
have a notification action when this guard is enabled.

Capture the created profile ARNs:

```bash
terraform output -json inference_profile_arns
```

For strict SCP enforcement, copy only the approved AIP ARNs into
`approved_application_inference_profile_arns` in the management tfvars. The
management plan must not be generated until this list is populated. The child
state also outputs `identity_center_bedrock_inference_policy_json`; review it
and attach it through the customer's existing IAM Identity Center workflow.
For CloudTrail API-to-selector coverage, see
[`docs/bedrock-audit-event-coverage.md`](docs/bedrock-audit-event-coverage.md).

## Step 5 — Deploy management resources

Initialize Terraform with the management backend, then plan and review before
applying.

```bash
terraform init -reconfigure -backend-config=deployment_accounts/example/management_backend.hcl
terraform plan  -var-file=deployment_accounts/example/management.tfvars
terraform apply -var-file=deployment_accounts/example/management.tfvars
```

This creates the SCP and attaches it to the account/OU IDs listed in
`scp_target_ids`. In strict mode, the SCP allows only the exact AIP ARNs listed
in `approved_application_inference_profile_arns`. The default compatibility
mode retains the historical same-account AIP wildcard; enable strict mode for
new POCs and migrate existing environments deliberately.

To activate cost-allocation tags, set `cost_allocation_tag_keys` in management
tfvars (for example `Project` and `Team`) after child resources with those tags
exist. This requires `ce:ListCostAllocationTags` and
`ce:UpdateCostAllocationTagsStatus` in the management/billing account. Cost
Explorer data is delayed until AWS processes usage; Terraform does not create a
dashboard or guarantee immediate cost visibility. See
[`docs/cost-allocation-tags.md`](docs/cost-allocation-tags.md).

> **Important:** Always run `terraform init -reconfigure` with the correct backend file before each management or child plan/apply. The two states share the same bucket but use different state keys. Omitting `-reconfigure` will silently use whichever backend was last initialized.

## Subsequent deployments

After initial setup, the workflow for each change is:

1. Switch to the correct backend (`-reconfigure`) for the state you are modifying.
2. Run `plan` then `apply` with the matching tfvars file.
3. Repeat for the other state if needed.
