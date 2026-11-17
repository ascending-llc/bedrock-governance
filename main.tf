module "bedrock_governance" {
  source = "./modules/bedrock_governance"

  resource_name_prefix                            = var.resource_name_prefix
  deployment_mode                                 = var.deployment_mode
  alarm_email                                     = var.alarm_email
  alarm_sns_topic_arn                             = var.alarm_sns_topic_arn
  require_alarm_notification                      = var.require_alarm_notification
  scp_target_ids                                  = var.scp_target_ids
  approved_application_inference_profile_arns     = var.approved_application_inference_profile_arns
  enforce_approved_application_inference_profiles = var.enforce_approved_application_inference_profiles
  approved_codex_inference_profile_arns           = var.approved_codex_inference_profile_arns
  approved_codex_project_arns                     = var.approved_codex_project_arns
  direct_access_model_id_patterns                 = var.direct_access_model_id_patterns
  cost_allocation_tag_keys                        = var.cost_allocation_tag_keys
  model_sources                                   = var.model_sources
  break_glass_principal_arns                      = var.break_glass_principal_arns
  audit_log_retention_days                        = var.audit_log_retention_days
  allow_codex_scp_exceptions                      = var.allow_codex_scp_exceptions
  enable_bedrock_mantle_data_events               = var.enable_bedrock_mantle_data_events
  deny_bedrock_mantle_inference                   = var.deny_bedrock_mantle_inference
  cost_alert_threshold_percent                    = var.cost_alert_threshold_percent
  enforce_daily_cost_limits                       = var.enforce_daily_cost_limits
  cost_check_interval_minutes                     = var.cost_check_interval_minutes
  cost_limit_block_policy_role_names              = var.cost_limit_block_policy_role_names
}
