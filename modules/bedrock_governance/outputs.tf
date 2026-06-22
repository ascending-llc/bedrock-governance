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

output "scp_policy_id" {
  description = "Organizations SCP ID for management deployments."
  value       = try(aws_organizations_policy.bedrock_approved_models[0].id, null)
}
