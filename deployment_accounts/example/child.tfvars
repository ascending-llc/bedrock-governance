region               = "us-east-1"
resource_name_prefix = "bedrock-governance"
deployment_mode      = "child"

model_sources = [
  {
    name     = "claude-haiku-4-5"
    model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  },
  {
    name     = "nova-lite-v1"
    model_id = "amazon.nova-lite-v1:0"
  }
]
