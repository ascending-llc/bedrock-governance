output "inference_profile_arns" {
  description = "Map of model source name to Bedrock inference profile ARN."
  value       = module.bedrock_governance.inference_profile_arns
}

output "inference_profile_ids" {
  description = "Map of model source name to Bedrock inference profile ID (the CloudWatch ModelId dimension value)."
  value       = module.bedrock_governance.inference_profile_ids
}

output "anomaly_alarm_metric_model_ids" {
  description = "ModelId dimension value watched by each anomaly alarm."
  value       = module.bedrock_governance.anomaly_alarm_metric_model_ids
}

output "cloudtrail_name" {
  description = "CloudTrail name when deployment_mode is child."
  value       = module.bedrock_governance.cloudtrail_name
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail bucket name when deployment_mode is child."
  value       = module.bedrock_governance.cloudtrail_bucket_name
}

output "anomaly_alarm_names" {
  description = "Map of anomaly alarm logical key to alarm name."
  value       = module.bedrock_governance.anomaly_alarm_names
}

output "anomaly_alarm_actions" {
  description = "Notification actions configured for each anomaly alarm."
  value       = module.bedrock_governance.anomaly_alarm_actions
}

output "scp_policy_id" {
  description = "Organizations SCP ID when deployment_mode is management."
  value       = module.bedrock_governance.scp_policy_id
}

output "scp_policy_attachment_target_ids" {
  description = "Organization account/OU IDs to which the SCP is attached."
  value       = module.bedrock_governance.scp_policy_attachment_target_ids
}

output "identity_center_bedrock_inference_policy_json" {
  description = "Identity-based inference policy JSON for review and attachment to the customer's existing IAM Identity Center permission set."
  value       = module.bedrock_governance.identity_center_bedrock_inference_policy_json
}

output "bedrock_approved_models_scp_json" {
  description = "Rendered Organizations SCP document for review and policy tests."
  value       = module.bedrock_governance.bedrock_approved_models_scp_json
}

output "inference_profile_tags" {
  description = "Tags applied to each provisioned application inference profile."
  value       = module.bedrock_governance.inference_profile_tags
}

output "anomaly_alarm_tags" {
  description = "Tags applied to each CloudWatch anomaly alarm."
  value       = module.bedrock_governance.anomaly_alarm_tags
}

output "audit_bucket_tags" {
  description = "Tags applied to the audit bucket in child deployments."
  value       = module.bedrock_governance.audit_bucket_tags
}

output "cost_allocation_tag_status" {
  description = "Status of cost allocation tag activation managed by the management state."
  value       = module.bedrock_governance.cost_allocation_tag_status
}

output "cloudtrail_advanced_event_selectors" {
  description = "Advanced CloudTrail event selectors configured for the child trail."
  value       = module.bedrock_governance.cloudtrail_advanced_event_selectors
}

output "audit_log_expiration_days" {
  description = "Retention (days) applied to CloudTrail log objects in the child audit bucket."
  value       = module.bedrock_governance.audit_log_expiration_days
}

output "cost_limit_block_policy_arn" {
  description = "ARN of the managed policy the cost enforcer rewrites to deny profiles over their daily limit. Null when no profile sets daily_cost_limit_usd."
  value       = module.bedrock_governance.cost_limit_block_policy_arn
}

output "cost_limit_block_policy_name" {
  description = "Name of the cost-limit block policy. Reference it (path /) as a customer managed policy in each IAM Identity Center permission set that can invoke the profiles."
  value       = module.bedrock_governance.cost_limit_block_policy_name
}

output "cost_enforcer_function_name" {
  description = "Name of the cost limit enforcer Lambda function. Null when no profile sets pricing."
  value       = module.bedrock_governance.cost_enforcer_function_name
}

output "cost_alert_thresholds_usd" {
  description = "Estimated daily cost (USD) at which each profile's cost alert fires."
  value       = module.bedrock_governance.cost_alert_thresholds_usd
}

output "cost_alert_alarm_names" {
  description = "Map of model source name to its daily cost alert alarm name."
  value       = module.bedrock_governance.cost_alert_alarm_names
}

output "cost_limit_alarm_names" {
  description = "Map of model source name to its daily cost limit alarm name."
  value       = module.bedrock_governance.cost_limit_alarm_names
}

output "cost_alert_alarm_actions" {
  description = "Notification actions configured for each cost alert alarm."
  value       = module.bedrock_governance.cost_alert_alarm_actions
}

output "cost_daily_limits_usd" {
  description = "Configured daily cost limit (USD) per profile."
  value       = module.bedrock_governance.cost_daily_limits_usd
}
