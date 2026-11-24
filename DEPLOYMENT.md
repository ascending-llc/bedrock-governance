# Deployment Guide

## Prerequisites

1. Terraform 1.9+
2. AWS CLI configured with credentials for both the management account and each child account
3. AWS Organizations enabled on the management account
4. The identity running the child state needs `sts:AssumeRole` on `BedrockGovernanceDeployer` in its own permission set; the role's trust policy alone is not enough
5. For cost-tag activation, `ce:ListCostAllocationTags` and `ce:UpdateCostAllocationTagsStatus` in the management/billing account

## Architecture overview

Deployment is split across two Terraform states:

- **Management state** — creates the Service Control Policy (SCP) and attaches it to target accounts/OUs. Runs with management-account credentials.
- **Child state** — creates Application Inference Profiles (AIPs), CloudTrail audit trail, CloudWatch anomaly alarms, and, when `model_sources` set `pricing`, the daily cost enforcer (Lambda, schedule, cost alarms, block policy). Runs by assuming a deploy role in the child account.

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

Copy the following values from the CloudFormation stack outputs into a per-customer copy of `deployment_accounts/example/` (for example `deployment_accounts/card-monroe/`); do not edit `example/` itself.

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

### Daily cost alerts and limits (optional)

Set `pricing` (USD per million tokens) on each `model_sources` entry you want
tracked, then `daily_cost_alert_usd` and/or `daily_cost_limit_usd`. See
[Daily cost limits](README.md#daily-cost-limits) for behavior and caveats.

1. Re-run `bootstrap/child_bootstrap.yaml` first on existing accounts; the deploy
   role needs the Lambda, EventBridge, Logs and scoped IAM permissions it now
   contains.
2. Apply the child state. Consider `enforce_daily_cost_limits = false` first to
   watch the alarms without blocking anyone.
3. Attach the block policy. Add `terraform output -raw cost_limit_block_policy_name`
   as a customer managed policy (path `/`) to each IAM Identity Center permission
   set that can invoke the profiles, or set `cost_limit_block_policy_role_names`
   for non-SSO roles. Create the policy in every account the permission set is
   provisioned to before referencing it.
4. Confirm the alarm email subscription, then run section H of
   [`docs/live-acceptance-checklist.md`](docs/live-acceptance-checklist.md).

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
tfvars (for example `Project`, `Team` and `Model`) after child resources with
those tags exist and have usage; billing can take about a day to recognize a new
tag. This requires `ce:ListCostAllocationTags` and
`ce:UpdateCostAllocationTagsStatus` in the management/billing account. Cost
Explorer data is delayed until AWS processes usage; Terraform does not create a
dashboard or guarantee immediate cost visibility. See
[`docs/cost-allocation-tags.md`](docs/cost-allocation-tags.md).

> **Important:** Always run `terraform init -reconfigure` with the correct backend file before each management or child plan/apply. The two states share the same bucket but use different state keys. Omitting `-reconfigure` will silently use whichever backend was last initialized.

## Step 6 — Test

Generate test traffic through each profile, then work through
[`docs/live-acceptance-checklist.md`](docs/live-acceptance-checklist.md),
substituting the account ID, resource prefix and profile IDs for the values at
the top of that document.

- The first invocation of each Anthropic model in an account creates an AWS
  Marketplace agreement and sends a notification email. The caller needs
  Marketplace permissions for this.
- Each invocation is logged once, as a CloudTrail management event; the Bedrock
  data selectors exclude those APIs and only capture async and bidirectional
  calls. See [`docs/bedrock-audit-event-coverage.md`](docs/bedrock-audit-event-coverage.md).
- The Identity Center administrator attaches
  `identity_center_bedrock_inference_policy_json` to the pilot permission set;
  then repeat the invocation and denial tests as a non-administrator user.
- Codex exemptions in the SCP are controlled by `allow_codex_scp_exceptions`
  (default `true` for backward compatibility); set it to `false` where Codex is
  not in scope.

## Step 7 — Roll out the desktop clients

The Claude and Codex desktop configuration is generated by the companion repo
[coding-agent-3p](https://github.com/ascending-llc/coding-agent-3p). It renders
standard macOS (`.mobileconfig`) and Windows (`.reg`, Codex `requirements.toml`)
policies plus the AWS CLI profile from one `config/config.json`. This repo
supplies the values it needs:

| `config.json` field | Source here |
|---|---|
| `aws.account_id`, `aws.bedrock_region` | Child account and `region` in `child.tfvars` |
| `aws.sso_start_url`, `aws.sso_region`, `aws.sso_role_name` | The customer's IAM Identity Center and the permission set that carries `identity_center_bedrock_inference_policy_json` (and the cost-limit block policy, if used) |
| `claude.models.<tier>.aip_arn` | `terraform output -json inference_profile_arns` |
| `claude.models.<tier>.anthropic_model_id` | The model behind each AIP: `aws bedrock get-inference-profile --inference-profile-identifier <aip_arn> --query 'models[].modelArn'` |
| `codex.models` | One entry per profile ID in `approved_codex_inference_profile_arns` (for example `global.openai.gpt-6.2-sol` and `global.openai.gpt-6.2-astra`); keep the two lists identical, since IAM, not Codex, enforces what a user can call |
| `codex.default_model` | The starting model; must be a key of `codex.models` (for example `global.openai.gpt-6.2-sol`) |

1. Complete Steps 4-6, including attaching the Identity Center policy to the
   permission set the clients will use.
2. In coding-agent-3p, fill in `config/config.json` and run
   `make policies PRODUCTS="claude codex"`. Follow its
   [admin guide](https://github.com/ascending-llc/coding-agent-3p/blob/main/docs/admin-guide.md)
   and [test plan](https://github.com/ascending-llc/coding-agent-3p/blob/main/docs/test-plan.md).
3. Distribute the macOS profiles through MDM and the Windows policy to the
   managed locations in the admin guide. Have each pilot user follow the
   [macOS](https://github.com/ascending-llc/coding-agent-3p/blob/main/docs/macos-user-guide.md)
   or [Windows](https://github.com/ascending-llc/coding-agent-3p/blob/main/docs/windows-user-guide.md)
   user guide.
4. Onboard the pilot users (the SOW calls for five, across Claude and Codex) and
   record each one in section I of
   [`docs/live-acceptance-checklist.md`](docs/live-acceptance-checklist.md).

Claude traffic goes through the AIPs, so it gets per-profile metrics, alarms and
cost limits. Codex uses system inference profiles and is attributed by IAM role
session in CloudTrail.

## Subsequent deployments

After initial setup, the workflow for each change is:

1. Switch to the correct backend (`-reconfigure`) for the state you are modifying.
2. Run `plan` then `apply` with the matching tfvars file.
3. Repeat for the other state if needed.
