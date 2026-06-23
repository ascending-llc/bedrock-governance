region               = "us-east-1"
resource_name_prefix = "bedrock-governance"
deployment_mode      = "child"
deploy_role_arn      = "arn:aws:iam::766796016661:role/BedrockGovernanceDeployer"

model_sources = [
  {
    name     = "claude-haiku-4-5"
    model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  },
  {
    name     = "claude-sonnet-4-6"
    model_id = "us.anthropic.claude-sonnet-4-6"
  }
]
