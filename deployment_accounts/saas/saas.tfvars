# Variables for the child-account deployment (AIPs, CloudTrail, alarms).
# Apply with: terraform apply -var-file=deployment_accounts/<your-account>/child.tfvars

region               = "us-east-1"          # e.g. "us-east-1"
resource_name_prefix = "bedrock-governance" # e.g. "bedrock-governance"
deployment_mode      = "child"

# ChildDeployRoleArn output from child_bootstrap.yaml CloudFormation stack
deploy_role_arn = "arn:aws:iam::897729109735:role/BedrockGovernanceDeployer"

# One AIP is created per entry. To track usage by team, create one entry per team per model.
# Each entry maps to its own CloudWatch anomaly alarm pair (input + output tokens).
# The team field is optional — omit it if you do not need team-level cost attribution.
model_sources = [
  {
    name     = "claude-code-claude-sonnet-5-5"
    model_id = "us.anthropic.claude-sonnet-5-5"
    team     = "development"
  },
  {
    name     = "claude-code-claude-opus-5-5"
    model_id = "us.anthropic.claude-opus-5-5"
    team     = "development"
  },
  {
    name     = "claude-code-claude-haiku-5-5"
    model_id = "us.anthropic.claude-haiku-5-5"
    team     = "development"
  },
  {
    name     = "openai-gpt-6-1-sol"
    model_id = "us.openai.gpt-6.1-sol"
    team     = "development"
  },
  {
    name     = "openai-gpt-6-1-terra"
    model_id = "us.openai.gpt-6.1-terra"
    team     = "development"
  },
  {
    name     = "openai-gpt-6-luna"
    model_id = "us.openai.gpt-6-luna"
    team     = "development"
  },
  {
    name     = "claude-code-nova-pro-v1"
    model_id = "amazon.nova-pro-v1:0"
    team     = "development"
  },
  {
    name     = "claude-code-nova-lite-v1"
    model_id = "amazon.nova-lite-v1:0"
    team     = "development"
  }
]
