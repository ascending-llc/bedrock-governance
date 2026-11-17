# bedrock_governance module

Governs Amazon Bedrock usage in an AWS Organization. Call it once per account role, selected by `deployment_mode`:

| `deployment_mode` | Run against | Creates |
|---|---|---|
| `child` | The account that runs inference | Application inference profiles, CloudTrail trail and audit bucket, anomaly and cost alarms, SNS topic, cost-enforcer Lambda and its managed deny policy |
| `management` | The Organizations management account | The approved-models SCP and its attachments, cost-allocation tag activation |

Apply `child` first: the management call needs the profile ARNs it produces.

## Usage

```hcl
module "bedrock_governance_child" {
  source = "git::https://github.com/ascending-llc/bedrock-governance.git//modules/bedrock_governance?ref=<release-tag>"

  providers = { aws = aws.child }

  deployment_mode      = "child"
  resource_name_prefix = "bedrock-governance"
  scp_target_ids       = []
  model_sources        = [{ name = "claude-sonnet", model_id = "us.anthropic.claude-sonnet-4-6", team = "platform" }]
}
```

See [examples/existing-terraform](../../examples/existing-terraform) for a complete child plus management setup. Keep account IDs, state buckets and role ARNs in your own repository, never in this one.

## Requirements

- Terraform `>= 1.9.0`; providers `hashicorp/aws ~> 5.99` and `hashicorp/archive ~> 2.4`.
- The module declares no provider configuration. Pass the caller's `aws` provider (or an alias via `providers = { aws = ... }`) for the right account.
- Child mode needs a deploy role with Bedrock, CloudTrail, S3, CloudWatch, SNS, Lambda, EventBridge, Logs and scoped IAM permissions. [`bootstrap/child_bootstrap.yaml`](../../bootstrap/child_bootstrap.yaml) creates one.
- Management mode needs Organizations policy permissions (`CreatePolicy`, `AttachPolicy` and related) and, for tag activation, Cost Explorer permissions (`ce:ListCostAllocationTags`, `ce:UpdateCostAllocationTagsStatus`).

## Inputs

Required: `resource_name_prefix`, `deployment_mode`, `scp_target_ids` (use `[]` in child mode) and `model_sources` (use `[]` in management mode).

| Name | Mode | Default | Description |
|---|---|---|---|
| `model_sources` | child | `[]` | One entry per profile: `name`, `model_id`, optional `team`, optional `pricing`, `daily_cost_limit_usd`, `daily_cost_alert_usd`. Cost features need `pricing`. |
| `alarm_email` / `alarm_sns_topic_arn` | child | `null` | At most one anomaly and cost alarm target. |
| `audit_log_retention_days` | child | `30` | CloudTrail log retention, minimum 30. |
| `enable_bedrock_mantle_data_events` | child | `false` | Also record `bedrock-mantle` project events (Codex). |
| `approved_codex_inference_profile_arns`, `approved_codex_project_arns` | child | `[]` | Included in the generated Identity Center policy. |
| `cost_alert_threshold_percent` | child | `80` | Alert percentage of each daily limit. |
| `enforce_daily_cost_limits` | child | `true` | `false` reports limit breaches without blocking. |
| `cost_check_interval_minutes` | child | `5` | Cost enforcer schedule. |
| `cost_limit_block_policy_role_names` | child | `[]` | Roles that receive the cost-limit block policy. |
| `scp_target_ids` | management | none | Account or OU IDs the SCP attaches to. |
| `enforce_approved_application_inference_profiles` | management | `false` | Strict mode: allow only the profile ARNs below. |
| `approved_application_inference_profile_arns` | management | `[]` | Exact profile ARNs, normally the child module's `inference_profile_arns`. |
| `direct_access_model_id_patterns` | management | `[]` | Model ID globs exempt from the profile requirement. |
| `break_glass_principal_arns` | management | `[]` | Principals exempt from the SCP denies. |
| `allow_codex_scp_exceptions` | management | `true` | Exempt Global OpenAI system profiles and `project/default`. |
| `deny_bedrock_mantle_inference` | management | `false` | Deny `bedrock-mantle:CreateInference`. |
| `cost_allocation_tag_keys` | management | `[]` | Tag keys to activate for Cost Explorer. |

Full descriptions and validations are in [variables.tf](variables.tf).

## Outputs

| Name | Mode | Description |
|---|---|---|
| `inference_profile_arns`, `inference_profile_ids` | child | Profile ARNs and IDs (the ID is the CloudWatch `ModelId` dimension). |
| `identity_center_bedrock_inference_policy_json` | child | Policy to attach to your Identity Center permission set. |
| `cost_limit_block_policy_name` | child | Reference as a customer managed policy in permission sets. |
| `cloudtrail_name`, `cloudtrail_bucket_name` | child | Audit trail and bucket. |
| `scp_policy_id`, `scp_policy_attachment_target_ids` | management | SCP and where it is attached. |

More outputs (alarm names, tags, cost thresholds, rendered SCP JSON) are defined in [outputs.tf](outputs.tf).
