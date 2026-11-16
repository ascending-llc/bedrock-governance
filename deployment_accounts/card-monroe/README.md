# Card Monroe POC Deployment

Configuration for deploying the Bedrock governance POC into Card Monroe's AWS
environment. Based on a validated internal sandbox deployment (kept out of this
repository).

## Fill in before starting

| Placeholder | Where | Source |
| --- | --- | --- |
| `<CHILD_ACCOUNT_ID>` | both tfvars | The POC account that will host profiles, trail and alarms. |
| `<STATE_BUCKET_NAME>`, `<LOCK_TABLE_NAME>` | both backend files | Outputs of `bootstrap/management_bootstrap.yaml`. |
| `deploy_role_arn` | `child.tfvars` | `ChildDeployRoleArn` output of `bootstrap/child_bootstrap.yaml`. |
| `<ALERT_EMAIL_ADDRESS>` | `child.tfvars` | Agreed alert recipient (confirm the SNS subscription after apply). |
| `<*_PROFILE_ID>` | `management.tfvars` | Child output `inference_profile_arns`, after the child apply. |

Confirm with the customer before the first apply:

- The management (Organizations) account, and who holds credentials for it.
- The approved model list (`model_sources`) and that each model is available in
  the account and Region.
- Whether Codex is in scope. If not, keep `allow_codex_scp_exceptions = false`
  (the default in this folder). If so, set it to true, add the
  `approved_codex_*` ARNs, and decide on `enable_bedrock_mantle_data_events`.
- Audit log retention (`audit_log_retention_days`, default 30).
- Whether a break-glass role is required (`docs/scp-break-glass.md`).
- The target for the SCP (the POC account for now) and what other SCPs apply
  there.
- Who attaches the generated policy to the Identity Center permission set.

## Prerequisites

- Terraform 1.9 or later (1.10 or later if you switch the backends to
  `use_lockfile`).
- Management-account credentials for the state bucket and the SCP, and
  permission to run `organizations:CreatePolicy` and `AttachPolicy`.
- `sts:AssumeRole` on `BedrockGovernanceDeployer` for whoever runs the child
  state; the role's trust policy alone is not enough. Run one child `plan`
  through the role before the live session.
- `ce:ListCostAllocationTags` and `ce:UpdateCostAllocationTagsStatus` in the
  billing/management account for the cost-tag step.
- A pilot user to test with, who is not an administrator.

Verify the identity before every init (`aws sts get-caller-identity`), and do
not leave `AWS_PROFILE` exported between sessions.

## Runbook

Follow [`DEPLOYMENT.md`](../../DEPLOYMENT.md) for the bootstrap stacks (steps 1
and 2), using these files in place of `deployment_accounts/example/`. Then:

```bash
# 1. Child state
terraform init -reconfigure -backend-config=deployment_accounts/card-monroe/child_backend.hcl
terraform plan  -var-file=deployment_accounts/card-monroe/child.tfvars -out=/tmp/cm-child.tfplan
terraform show  -no-color /tmp/cm-child.tfplan      # review; expect adds only on first run
terraform apply /tmp/cm-child.tfplan

terraform output -json inference_profile_arns        # copy into management.tfvars
terraform output -raw identity_center_bedrock_inference_policy_json

# 2. Management state (only after the ARNs are filled in)
terraform init -reconfigure -backend-config=deployment_accounts/card-monroe/management_backend.hcl
terraform plan  -var-file=deployment_accounts/card-monroe/management.tfvars -out=/tmp/cm-mgmt.tfplan
terraform show  -no-color /tmp/cm-mgmt.tfplan        # scp_target_ids must be exactly the POC account
terraform apply /tmp/cm-mgmt.tfplan
```

## Test

1. Generate test traffic (checklist section A) before checking metrics and logs.
   The first invocation of each Anthropic model in a new account creates an AWS
   Marketplace agreement and sends a notification email; the caller needs
   Marketplace permissions for that, and the customer should expect the emails.
2. Run `docs/live-acceptance-checklist.md` sections A to G. Substitute the
   account ID, resource prefix and profile IDs from this deployment for the
   sandbox values at the top of that document, and record evidence per row.
3. Have the customer's Identity Center administrator attach the generated
   policy, then repeat the invocation and denial tests as the pilot user.
4. Configure and test the engineers' clients (Claude Code and, if in scope,
   Codex) using [`INTEGRATIONS.md`](INTEGRATIONS.md).

Known behavior to explain to the customer:

- Each invocation is logged once, as a CloudTrail management event; the Bedrock
  data selectors exclude those APIs and only capture async and bidirectional
  calls. See `docs/bedrock-audit-event-coverage.md`.
- Anomaly alarms need days of usage history before the band is meaningful, and
  an alert can take 2 to 3 hours after a breach (hourly period, 2 of 3
  datapoints).
- Cost-tag data lags by about a day, and tags are not retroactive.

## Rollback

Remove the SCP first (`terraform destroy` with the management backend, or detach
via Organizations), then the child state. Do not delete the state bucket.
