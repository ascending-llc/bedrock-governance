module "bedrock_governance" {
  source = "./modules/bedrock_governance"

  resource_name_prefix            = var.resource_name_prefix
  deployment_mode                 = var.deployment_mode
  alarm_email                     = var.alarm_email
  scp_target_ids                  = var.scp_target_ids
  direct_access_model_id_patterns = var.direct_access_model_id_patterns
  model_sources                   = var.model_sources
}
