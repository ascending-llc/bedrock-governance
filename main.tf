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
}
