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
#
# Optional cost controls (per entry):
#   pricing              USD per million tokens; required for any cost feature (copy from the Bedrock pricing page).
#   daily_cost_alert_usd alert when the estimated UTC-day cost reaches this amount.
#   daily_cost_limit_usd block the profile for the rest of the UTC day at this amount; also alerts at
#                        cost_alert_threshold_percent (default 80%) unless daily_cost_alert_usd is set.
# Estimates come from CloudWatch token metrics, not billing data; see the README "Daily cost limits" section.
model_sources = [
  {
    name     = "platform-claude-sonnet-4-6"
    model_id = "us.anthropic.claude-sonnet-4-6"
    team     = "platform"
    pricing = {
      input_per_million       = 3.00
      output_per_million      = 15.00
      cache_read_per_million  = 0.30
      cache_write_per_million = 3.75
    }
    daily_cost_limit_usd = 50
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
