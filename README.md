# Bedrock Governance

Terraform implementation for governing Amazon Bedrock usage across an AWS Organization. Provides account-scoped Application Inference Profiles (AIPs), providing per-model anomaly detection, audit-ready logs, and SCP-enforced access control.

## Features

| Feature | Description |
|---|---|
| **AIP Provisioning** | Terraform-managed Application Inference Profiles for each model. |
| **Per-Model Anomaly Detection** | CloudWatch anomaly alarms on input and output token usage per AIP. Alerts when usage deviates from learned baselines. POCs can require an email-to-SNS or existing SNS notification target. |
| **Alarm Delivery** | Configure an email-to-SNS subscription or an existing SNS topic ARN. POCs can require exactly one notification target. |
| **Audit-Ready Logs** | Multi-region CloudTrail trail captures all Bedrock `InvokeModel` and async invocation events. Logs are encrypted, versioned, and retained for 30 days in an S3 bucket. |
| **Access Control** | SCP strict mode allows only explicitly approved AIP ARNs and denies direct foundation-model invocations. A legacy compatibility mode retains same-account AIP wildcard behavior. |
| **Identity Center Policy** | Child-state output provides a least-privilege inference policy JSON for review and attachment to the customer's existing IAM Identity Center permission set. |
| **Resource Tags** | Terraform applies Project, ManagedBy, and DeploymentMode tags to managed resources; optional Team tags distinguish profiles and alarms. |
| **Cost Allocation** | Management state activates selected user-defined tags such as Project and Team for Cost Explorer/CUR after tagged child resources exist; billing visibility follows AWS processing. |

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
│   ├── bedrock-governance-openai-gpt-6-1-sol
│   ├── bedrock-governance-openai-gpt-6-1-terra
│   └── bedrock-governance-openai-gpt-6-luna
├── CloudWatch Anomaly Alarms (input + output tokens, per AIP)
└── CloudTrail → S3 Audit Bucket
    └── Events: Management + Bedrock Model + Async Invocations
```

Requests flow: **caller → AIP ARN → foundation model**. The SCP allows invocations that carry an AIP ARN and denies all direct foundation-model calls. AIPs are account-scoped, so every request is tied to a specific account and profile.

## Repository layout

```
|- main.tf                      # Root orchestration entrypoint
|- backend.tf                   # Backend block (values sourced from backend config files)
|- bootstrap/
|  |- management_bootstrap.yaml # Management bootstrap (Terraform state backend)
|  |- child_bootstrap.yaml      # Child bootstrap (Terraform deploy role)
|- deployment_accounts/
|  |- management_backend.hcl    # Backend settings for management state
|  |- child_backend.hcl         # Backend settings for child state
|  |- management.tfvars         # Vars for management deployment
|  |- child.tfvars              # Vars for child deployment
|- modules/
|  |- bedrock_governance/       # Bedrock Governance Terraform module
```

## Getting started

See [DEPLOYMENT.md](DEPLOYMENT.md) for full step-by-step deployment instructions.

See [INTEGRATIONS.md](INTEGRATIONS.md) for how to connect Claude Code to your deployed AIPs.

See [docs/identity-center-permissions.md](docs/identity-center-permissions.md) for the generated IAM Identity Center policy workflow.

See [docs/cost-allocation-tags.md](docs/cost-allocation-tags.md) for tag activation and billing visibility prerequisites, and [docs/bedrock-audit-event-coverage.md](docs/bedrock-audit-event-coverage.md) for CloudTrail Runtime event coverage.

