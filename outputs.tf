output "inference_profile_arns" {
  description = "Map of model source name to Bedrock inference profile ARN."
  value       = module.bedrock_governance.inference_profile_arns
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

output "scp_policy_id" {
  description = "Organizations SCP ID when deployment_mode is management."
  value       = module.bedrock_governance.scp_policy_id
}
