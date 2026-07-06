# Variables for the child-account deployment (AIPs, CloudTrail, alarms).
# Apply with: terraform apply -var-file=deployment_accounts/<your-account>/child.tfvars

region               = "<AWS_REGION>"           # e.g. "us-east-1"
resource_name_prefix = "<RESOURCE_NAME_PREFIX>" # e.g. "bedrock-governance"
deployment_mode      = "child"

# ChildDeployRoleArn output from child_bootstrap.yaml CloudFormation stack
deploy_role_arn = "arn:aws:iam::<CHILD_ACCOUNT_ID>:role/BedrockGovernanceDeployer"

# Optional — if set, creates an SNS topic and email subscription for anomaly alarm notifications.
# After apply, check your inbox and confirm the subscription before alerts will be delivered.
alarm_email = "<ALERT_EMAIL_ADDRESS>"

# One AIP is created per entry. To track usage by team, create one entry per team per model.
# Each entry maps to its own CloudWatch anomaly alarm pair (input + output tokens).
# The team field is optional — omit it if you do not need team-level cost attribution.
model_sources = [
  {
    name     = "platform-claude-sonnet-4-6"
    model_id = "us.anthropic.claude-sonnet-4-6"
    team     = "platform"
  },
  {
    name     = "dev-claude-sonnet-4-6"
    model_id = "us.anthropic.claude-sonnet-4-6"
    team     = "development"
  },
  {
    name     = "platform-claude-haiku-4-5"
    model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    team     = "platform"
  },
  {
    name     = "dev-claude-haiku-4-5"
    model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    team     = "development"
  }
]
