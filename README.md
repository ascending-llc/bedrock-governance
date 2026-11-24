# Bedrock Governance

Terraform implementation for governing Amazon Bedrock usage across an AWS Organization. It is the account-guardrails half of the open-source 3P governance solution described in [3P Governance on Amazon Bedrock](https://ascendingdc.com/jarvis-ai/3p-governance-on-amazon-bedrock/); the client-configuration half is [coding-agent-3p](https://github.com/ascending-llc/coding-agent-3p).

Clients such as Claude Desktop, Claude Code, ChatGPT Desktop and Codex send inference to Bedrock in your AWS account (3P) instead of a vendor-hosted service. Client settings only choose the route. This module provides the controls that decide what is allowed, record what happened, and cap what it costs: account-scoped Application Inference Profiles (AIPs), SCP-enforced access control, per-profile anomaly detection, daily cost alerts and limits, and audit-ready logs.

## Features

| Feature | Description |
|---|---|
| **AIP Provisioning** | One Terraform-managed Application Inference Profile per model (and per team, if you want team-level attribution). Usage and cost attach to a named, tagged resource. |
| **Access Control (SCP)** | Strict mode allows only explicitly approved AIP ARNs and denies direct foundation-model invocations. A legacy compatibility mode retains same-account AIP wildcard behavior. Optional break-glass principals are exempted, and an optional statement denies `bedrock-mantle:CreateInference`. |
| **Daily Cost Limit per AIP** | Set a USD limit per profile (for example `$50` per day). A scheduled Lambda estimates each profile's spend from its CloudWatch token metrics and, when the limit is reached, denies invocation of that profile until the UTC day rolls over or the limit is raised. See [Daily cost limits](#daily-cost-limits). |
| **Daily Cost Alerts per AIP** | A CloudWatch alarm per profile fires when its estimated daily cost reaches an explicit USD threshold, or a percentage of its limit (80% by default). A second alarm reports when a profile is blocked. |
| **Per-Model Anomaly Detection** | CloudWatch anomaly alarms on input and output token usage per AIP. Alerts when usage deviates from learned baselines. |
| **Alarm Delivery** | Configure an email-to-SNS subscription or an existing SNS topic ARN. POCs can require exactly one notification target. All anomaly, cost and enforcer-failure alarms use the same target. |
| **Audit-Ready Logs** | Multi-region CloudTrail trail captures Bedrock `InvokeModel`/`Converse` management events and async or bidirectional data events (optionally `bedrock-mantle` project events for Codex). Logs are encrypted, versioned, and retained in S3 (30 days by default, configurable). |
| **Identity Center Policy** | Child-state output provides a least-privilege inference policy JSON for review and attachment to the customer's existing IAM Identity Center permission set, including optional Codex system profiles and projects. |
| **Resource Tags** | Terraform applies Project, ManagedBy, DeploymentMode and Model tags to managed resources; optional Team tags distinguish profiles and alarms. |
| **Cost Allocation** | Management state activates selected user-defined tags such as Project, Team and Model for Cost Explorer/CUR after tagged child resources exist; billing visibility follows AWS processing. |
| **Codex / ChatGPT Desktop Support** | Codex uses Runtime system profiles instead of AIPs. The SCP carries a temporary, switchable exception for Global OpenAI system profiles and the default project; IAM limits which models are approved. |
| **Multi-Account Deployment** | Two Terraform states: management (SCP, tag activation) and child (profiles, trail, alarms, cost enforcer). CloudFormation bootstrap templates and StackSets create deployment roles across an OU. |

## Architecture

```
Management Account
└── SCP: DenyDirectFoundationModelInvocations
    └── Attached to target account(s) / OU(s)

Child Account
├── Application Inference Profiles (one per model)
│   ├── bedrock-governance-claude-code-claude-sonnet-5-5
│   ├── bedrock-governance-claude-code-claude-opus-5-5
│   ├── bedrock-governance-claude-code-claude-haiku-5-5
│   ├── bedrock-governance-openai-gpt-6-2-sol
│   └── bedrock-governance-openai-gpt-6-2-astra
├── CloudWatch Anomaly Alarms (input + output tokens, per AIP)
├── Cost Control (per priced AIP)
│   ├── EventBridge schedule → Lambda cost enforcer
│   ├── Custom metrics: EstimatedDailyCostUSD, CostLimitBlocked
│   ├── Alarms: daily cost alert, daily cost limit reached, enforcer errors
│   └── Managed deny policy "<prefix>-bedrock-cost-limit-block" (rewritten by the Lambda)
└── CloudTrail → S3 Audit Bucket
    └── Events: Management + Bedrock Model + Async Invocations
```

Requests flow: **caller → AIP ARN → foundation model**. The SCP allows invocations that carry an AIP ARN and denies all direct foundation-model calls. AIPs are account-scoped, so every request is tied to a specific account and profile.

## What is enforced where

Client settings choose the route; only AWS-side controls are authorization boundaries.

| Control | Layer | Enforces? | What it does |
|---|---|---|---|
| Claude Code `availableModels`, `requirements.toml` | Client managed settings ([coding-agent-3p](https://github.com/ascending-llc/coding-agent-3p)) | No | Choose the route and defaults; not a model allowlist. |
| IAM permission set (generated policy) | AWS IAM Identity Center | Yes | Authorizes which profiles and models a person may invoke. |
| Service control policy | AWS Organizations | Yes | Denies direct foundation-model calls and non-approved profiles. |
| Cost-limit block policy | IAM (customer managed policy) | Yes | Denies a profile after its estimated daily cost reaches its limit. Applies only to roles it is attached to. |
| CloudTrail | AWS account | Audit | Records who called what; does not block. |
| Anomaly, cost-alert and cost-limit alarms | AWS account | Alert | Notify on unusual usage or on reaching a cost threshold. |

## Daily cost limits

Bedrock does not emit a spend event per inference profile, so the module estimates cost itself:

1. Each `model_sources` entry that sets `pricing` (USD per million tokens) is tracked.
2. A Lambda runs every `cost_check_interval_minutes` (default 5). It sums today's (UTC) `InputTokenCount`, `OutputTokenCount`, `CacheReadInputTokenCount` and `CacheWriteInputTokenCount` metrics for the profile and multiplies by the configured prices.
3. It publishes `EstimatedDailyCostUSD` and `CostLimitBlocked` metrics (namespace `BedrockGovernance`, dimension `ModelId` = profile ID). The cost-alert and limit alarms watch these and notify the configured SNS target.
4. For profiles with `daily_cost_limit_usd`, the Lambda rewrites the managed policy `<prefix>-bedrock-cost-limit-block` so it denies `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on every profile at or over its limit. IAM evaluates the policy on each request, so active sessions are blocked as well.
5. The block is recomputed from today's usage on every run. It lifts automatically after 00:00 UTC, or on the next run after you raise the limit.

```hcl
model_sources = [
  {
    name     = "platform-claude-sonnet-4-6"
    model_id = "us.anthropic.claude-sonnet-4-6"
    team     = "platform"
    pricing = {
      input_per_million       = 3.00
      output_per_million      = 15.00
      cache_read_per_million  = 0.30
      cache_write_per_million = 3.75
    }
    daily_cost_limit_usd = 50 # block at $50/day; alerts at 80% ($40) by default
  },
  {
    name                 = "dev-claude-haiku-4-5"
    model_id             = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    team                 = "development"
    pricing              = { input_per_million = 1.00, output_per_million = 5.00 }
    daily_cost_alert_usd = 10 # alert only, never blocks
  }
]
```

Related variables: `cost_alert_threshold_percent`, `enforce_daily_cost_limits` (set `false` for a dry run that alarms but does not block), `cost_check_interval_minutes`, `cost_limit_block_policy_role_names`.

**Attach the block policy.** Terraform creates the policy but does not know your principals. Either reference `cost_limit_block_policy_name` as a customer managed policy (path `/`) in each IAM Identity Center permission set that can invoke the profiles (the policy must exist in every account the permission set is provisioned to), or list non-SSO role names in `cost_limit_block_policy_role_names`. Without an attachment the limit alerts but blocks no one.

**Limits to understand before relying on it:**

- It is an estimate from CloudWatch token metrics at the prices you configure, not billing data. Metrics lag by a few minutes and the check runs on a schedule, so spend can exceed the limit before the block lands.
- Long-context or other tiered price surcharges are not modelled; configure prices that cover your usage pattern or set the limit with margin.
- If the Lambda cannot run, enforcement fails open. The `...-bedrock-cost-limit-enforcer-errors` alarm reports this.
- Only AIP traffic is tracked. Codex and ChatGPT Desktop use Runtime system profiles; attribute their usage by role session in CloudTrail.
- The deploy role needs Lambda, EventBridge, CloudWatch Logs and scoped IAM permissions; `bootstrap/child_bootstrap.yaml` includes them.

## Repository layout

```
|- main.tf                      # Root orchestration entrypoint
|- backend.tf                   # Backend block (values sourced from backend config files)
|- bootstrap/
|  |- management_bootstrap.yaml # Management bootstrap (Terraform state backend)
|  |- child_bootstrap.yaml      # Child bootstrap (Terraform deploy role)
|- deployment_accounts/
|  |- example/                  # Template: copy per customer, do not edit in place
|  |  |- management_backend.hcl # Backend settings for management state
|  |  |- child_backend.hcl      # Backend settings for child state
|  |  |- management.tfvars      # Vars for management deployment
|  |  |- child.tfvars           # Vars for child deployment
|- modules/
|  |- bedrock_governance/       # Bedrock Governance Terraform module
|  |  |- cost_control.tf        # Cost enforcer Lambda, schedule, alarms, block policy
|  |  |- lambda/                # Cost enforcer source and unit tests
|- tests/                       # terraform test suite (mock provider)
|- docs/                        # Operational guides
```

## Getting started

Rollout has four steps: AWS prerequisites (IAM Identity Center, a Bedrock permission set, this module), generate client configuration with [coding-agent-3p](https://github.com/ascending-llc/coding-agent-3p), distribute it (MDM on macOS, managed locations on Windows), then verify both successful calls and denied requests.

- [DEPLOYMENT.md](DEPLOYMENT.md): full step-by-step deployment.
- [INTEGRATIONS.md](INTEGRATIONS.md): connect Claude Code to your deployed AIPs.
- [docs/identity-center-permissions.md](docs/identity-center-permissions.md): generated IAM Identity Center policy workflow.
- [docs/cost-allocation-tags.md](docs/cost-allocation-tags.md): tag activation and billing visibility prerequisites.
- [docs/bedrock-audit-event-coverage.md](docs/bedrock-audit-event-coverage.md): CloudTrail runtime event coverage.
- [docs/scp-break-glass.md](docs/scp-break-glass.md): break-glass exemptions from the SCP.
- [docs/live-acceptance-checklist.md](docs/live-acceptance-checklist.md): verify the deployed controls.

## Testing

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
python3 -m unittest discover -s modules/bedrock_governance/lambda -v
```

## Open source and support

This repository and coding-agent-3p are open source and free. ASCENDING offers implementation, configuration and support as a paid engagement, including a 3-business-day deployment of both layers with sign-in configuration and operations runbooks. See the [3P governance page](https://ascendingdc.com/jarvis-ai/3p-governance-on-amazon-bedrock/).

