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
    name     = "claude-code-claude-sonnet-5"
    model_id = "us.anthropic.claude-sonnet-5"
    team     = "development"
  },
  {
    name     = "claude-code-claude-haiku-4-5"
    model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
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
