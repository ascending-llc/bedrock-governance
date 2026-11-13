# Sandbox Test Deployment Guide

This guide is prefilled for the isolated governance POC.

| Setting | Value |
| --- | --- |
| Management account | `595312265488` |
| Child sandbox account | `806709759688` |
| Region | `us-east-1` |
| Target branch | `feature/AS-1990` |
| Configuration directory | `deployment_accounts/sandbox-806709759688/` |

This deployment does not use or modify `deployment_accounts/saas/` or its
Terraform state. An authorized operator must run all applies during the
screen-share and review each plan before applying.

## 1. Plan the Child Deployment

Run from the governance repository root:

```bash
terraform init -reconfigure \
  -backend-config=deployment_accounts/sandbox-806709759688/child_backend.hcl

terraform plan \
  -var-file=deployment_accounts/sandbox-806709759688/child.tfvars \
  -out=/tmp/bedrock-sandbox-child.tfplan

terraform show -no-color /tmp/bedrock-sandbox-child.tfplan
```

Review the plan and confirm the provider assumes `BedrockGovernanceDeployer` in
account `806709759688` then Apply:

```bash
terraform apply /tmp/bedrock-sandbox-child.tfplan
```

## 2. Add the Approved Profile ARNs

After the child apply, retrieve the created profile ARNs:

```bash
terraform output -json inference_profile_arns
```

Copy only the approved profile ARNs into
`approved_application_inference_profile_arns` in
`deployment_accounts/sandbox-806709759688/management.tfvars`. Strict mode
rejects an empty list.

## 3. Plan the Management Deployment

Reinitialize Terraform with the management backend, then plan and inspect the
changes:

```bash
terraform init -reconfigure \
  -backend-config=deployment_accounts/sandbox-806709759688/management_backend.hcl

terraform plan \
  -var-file=deployment_accounts/sandbox-806709759688/management.tfvars \
  -out=/tmp/bedrock-sandbox-management.tfplan

terraform show -no-color /tmp/bedrock-sandbox-management.tfplan
```

Before applying, confirm that the SCP target is only account `806709759688` and
that the plan activates the configured `Project` and `Team` cost-allocation
tags. Apply only after approval:

```bash
terraform apply /tmp/bedrock-sandbox-management.tfplan
```

## 4. Attach the Identity Center Policy

From the child state, inspect the generated permission policy:

```bash
terraform init -reconfigure \
  -backend-config=deployment_accounts/sandbox-806709759688/child_backend.hcl

terraform output -raw identity_center_bedrock_inference_policy_json
```

Have the customer's IAM Identity Center administrator review and attach the
policy to the existing permission set. Terraform does not assign the permission
set to users or groups.
