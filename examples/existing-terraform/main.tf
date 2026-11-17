# Example: use the module from an existing Terraform repository.
# Copy into your own repository, replace every <PLACEHOLDER> and 123456789012 (a dummy account ID), and keep real values there only.
# Replace the local source below with the git source and a release tag:
#   git::https://github.com/ascending-llc/bedrock-governance.git//modules/bedrock_governance?ref=<release-tag>

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
  }
}

provider "aws" {
  alias  = "child"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/BedrockGovernanceDeployer"
  }
}

provider "aws" {
  alias  = "management"
  region = "us-east-1"
}

module "bedrock_governance_child" {
  source    = "../../modules/bedrock_governance"
  providers = { aws = aws.child }

  deployment_mode      = "child"
  resource_name_prefix = "<RESOURCE_NAME_PREFIX>"
  scp_target_ids       = []
  alarm_email          = "<ALERT_EMAIL_ADDRESS>"

  model_sources = [
    {
      name     = "claude-sonnet"
      model_id = "us.anthropic.claude-sonnet-4-6"
      team     = "<TEAM>"
    }
  ]
}

# Needs Organizations permissions in the management account.
module "bedrock_governance_management" {
  source    = "../../modules/bedrock_governance"
  providers = { aws = aws.management }

  deployment_mode      = "management"
  resource_name_prefix = "<RESOURCE_NAME_PREFIX>"
  scp_target_ids       = ["123456789012"]
  model_sources        = []

  enforce_approved_application_inference_profiles = true
  approved_application_inference_profile_arns     = values(module.bedrock_governance_child.inference_profile_arns)
  cost_allocation_tag_keys                        = ["Project", "Team", "Model"]
}

output "identity_center_bedrock_inference_policy_json" {
  value = module.bedrock_governance_child.identity_center_bedrock_inference_policy_json
}
