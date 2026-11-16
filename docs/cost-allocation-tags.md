# Cost Allocation Tags

The child state applies these tags to application inference profiles and
anomaly alarms:

| Tag | Value | Purpose |
| --- | --- | --- |
| `Project` | `bedrock-governance` | Groups all governance spend. |
| `ManagedBy` | `Terraform` | Ownership. |
| `DeploymentMode` | `child` | Deployment context. |
| `Model` | the `model_sources[].name` | Per-model cost grouping. |
| `Team` | the `model_sources[].team` (optional) | Per-team cost grouping. |

`Model` is what makes per-model attribution possible in Cost Explorer. Without
it, profiles for different models that share a `Team` value are
indistinguishable by tag. Per-team attribution still requires a separate
application inference profile per team and model, configured as separate
`model_sources` entries.

The management state activates tag keys for Cost Explorer/CUR using the
Terraform `aws_ce_cost_allocation_tag` resource. Set `cost_allocation_tag_keys`
only after the child resources carrying those tags exist. The sandbox
management tfvars activates `Project`, `Team` and `Model` after the child AIPs
are deployed; its output reports the requested tag status.

**Existing profiles:** adding the `Model` tag is an in-place tag update on each
profile (no replacement). Apply the child state, wait for the tag to appear in
billing data, then apply the management state.

## Prerequisites and limits

- The management/billing account role needs Cost Explorer permissions to list
  and activate cost allocation tags (`ce:ListCostAllocationTags` and
  `ce:UpdateCostAllocationTagsStatus`).
- AWS must recognize the tag keys from tagged resources before activation (this
  can take up to about 24 hours after first use); run the management plan after
  the child resources have been created and have served traffic.
- Activation is a Billing/Cost Explorer operation in the management or payer
  account, not a child-account operation.
- Activation enables cost grouping by those keys; it does not create a
  dashboard, budget, or hard spending cap.
- Cost Explorer/CUR visibility is delayed until billing data is processed.
  Billing data refreshes at least daily and may take longer. Do not represent
  tag activation alone as immediately available chargeback data.
- Tags are not retroactive: cost is grouped by tag only from the time the tag
  is activated.
- The customer Billing owner must confirm the required keys and the
  payer/billing account in which they should be activated.

The management state's `cost_allocation_tag_status` output records the requested
activation status for configured keys. Confirm the active keys and later-arriving
Cost Explorer/CUR data with the customer's Billing owner before calling
cost-allocation visibility accepted.
