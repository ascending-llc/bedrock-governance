# Cost Allocation Tags

The child state applies `Project`, `ManagedBy`, and `DeploymentMode` tags to
managed resources and preserves the optional `Team` tag on profiles and alarms.
Per-team attribution requires a separate application inference profile per team
and model, configured as separate `model_sources` entries.

The management state activates tag keys for Cost Explorer/CUR using the
Terraform `aws_ce_cost_allocation_tag` resource. Set `cost_allocation_tag_keys`
only after the child resources carrying those tags exist. The sandbox
management tfvars activates `Project` and `Team` after child AIPs are deployed;
its output reports the requested tag status. Cost data can then be grouped by
those tags when AWS reports the tagged usage.

## Prerequisites and limits

- The management/billing account role needs Cost Explorer permissions to list
  and activate cost allocation tags (`ce:ListCostAllocationTags` and
  `ce:UpdateCostAllocationTagsStatus`).
- AWS must recognize the tag keys from tagged resources before activation; run
  the management plan after the child resources have been created.
- Activation is a Billing/Cost Explorer operation in the management or payer
  account. The operator needs `ce:ListCostAllocationTags` and
  `ce:UpdateCostAllocationTagsStatus`.
- Cost-tag activation is a Billing/Cost Explorer operation in the management or
  payer account, not a child-account operation. The operator needs
  `ce:ListCostAllocationTags` and `ce:UpdateCostAllocationTagsStatus`.
- Activation enables cost grouping by those keys; it does not create a
  dashboard, budget, or hard spending cap.
- Cost Explorer/CUR visibility is delayed until billing data is processed. Do
  not represent tag activation alone as immediately available chargeback data.
- The customer Billing owner must confirm the required keys and the payer/billing
  account in which they should be activated.

The management state's `cost_allocation_tag_status` output records the requested
activation status for configured keys. Confirm the active keys and later-arriving
Cost Explorer/CUR data with the customer's Billing owner before calling
cost-allocation visibility accepted. Billing data refreshes at least daily and
may take longer; tag activation is not a dashboard, budget, real-time spending
cap, or immediate per-profile dollar report.