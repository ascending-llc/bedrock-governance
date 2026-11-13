output "inference_profile_arns" {
  description = "Map of model source name to Bedrock inference profile ARN."
  value       = { for key, profile in aws_bedrock_inference_profile.this : key => profile.arn }
}

output "cloudtrail_name" {
  description = "CloudTrail trail name for child deployments."
  value       = try(aws_cloudtrail.bedrock[0].name, null)
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail bucket name for child deployments."
  value       = try(aws_s3_bucket.bedrock_audit[0].bucket, null)
}

output "anomaly_alarm_names" {
  description = "Map of anomaly alarm key to alarm name."
  value       = { for key, alarm in aws_cloudwatch_metric_alarm.bedrock_anomaly : key => alarm.alarm_name }
}

output "anomaly_alarm_actions" {
  description = "Notification actions configured for each anomaly alarm."
  value       = { for key, alarm in aws_cloudwatch_metric_alarm.bedrock_anomaly : key => alarm.alarm_actions }
}

output "scp_policy_id" {
  description = "Organizations SCP ID for management deployments."
  value       = try(aws_organizations_policy.bedrock_approved_models[0].id, null)
}

output "scp_policy_attachment_target_ids" {
  description = "Organization account/OU IDs to which the SCP is attached."
  value       = [for attachment in values(aws_organizations_policy_attachment.bedrock_approved_models) : attachment.target_id]
}

output "identity_center_bedrock_inference_policy_json" {
  description = "Identity-based inference policy JSON for review and attachment to the customer's existing IAM Identity Center permission set."
  value       = local.identity_center_bedrock_inference_policy_json
}

output "bedrock_approved_models_scp_json" {
  description = "Rendered Organizations SCP document for review and policy tests."
  value       = try(aws_organizations_policy.bedrock_approved_models[0].content, null)
}

output "inference_profile_tags" {
  description = "Tags applied to each provisioned application inference profile."
  value       = { for key, profile in aws_bedrock_inference_profile.this : key => profile.tags }
}

output "anomaly_alarm_tags" {
  description = "Tags applied to each CloudWatch anomaly alarm."
  value       = { for key, alarm in aws_cloudwatch_metric_alarm.bedrock_anomaly : key => alarm.tags }
}

output "audit_bucket_tags" {
  description = "Tags applied to the audit bucket in child deployments."
  value       = try(aws_s3_bucket.bedrock_audit[0].tags, {})
}

output "cost_allocation_tag_status" {
  description = "Status of cost allocation tag activation managed by the management state."
  value       = { for key, tag in aws_ce_cost_allocation_tag.this : key => tag.status }
}

output "cloudtrail_advanced_event_selectors" {
  description = "Advanced CloudTrail event selectors configured for the child trail."
  value       = local.cloudtrail_advanced_event_selectors
}
