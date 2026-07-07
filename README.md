# Bedrock Governance

Terraform implementation for governing Amazon Bedrock usage across an AWS Organization. Provides account-scoped Application Inference Profiles (AIPs), providing per-model anomaly detection, audit-ready logs, and SCP-enforced access control.

## Features

| Feature | Description |
|---|---|
| **AIP Provisioning** | Terraform-managed Application Inference Profiles for each model. |
| **Per-Model Anomaly Detection** | CloudWatch anomaly alarms on input and output token usage per AIP. Alerts when usage deviates from learned baselines. |
| **Audit-Ready Logs** | Multi-region CloudTrail trail captures all Bedrock `InvokeModel` and async invocation events. Logs are encrypted, versioned, and retained for 30 days in an S3 bucket. |
| **Access Control** | Service Control Policy (SCP) blocks direct foundation-model invocations org-wide, ensuring requests are attributable and observable. |

## Architecture

```
Management Account
└── SCP: DenyDirectFoundationModelInvocations
    └── Attached to target account(s) / OU(s)

Child Account
├── Application Inference Profiles (one per model)
│   ├── bedrock-governance-claude-sonnet-4-6
│   └── bedrock-governance-claude-haiku-4-5
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

