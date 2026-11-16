# Child-account deployment (AIPs, CloudTrail, alarms) for the Card Monroe POC.
# Replace every <PLACEHOLDER> before planning; see README.md in this folder.
region               = "us-east-1"
resource_name_prefix = "bg-cm-<CHILD_ACCOUNT_ID>"
deployment_mode      = "child"

# ChildDeployRoleArn output of bootstrap/child_bootstrap.yaml. The person running
# Terraform also needs sts:AssumeRole on this role in their own permission set.
deploy_role_arn = "arn:aws:iam::<CHILD_ACCOUNT_ID>:role/BedrockGovernanceDeployer"

# Agreed alert recipient. Confirm the SNS subscription email after the first apply.
alarm_email                = "<ALERT_EMAIL_ADDRESS>"
require_alarm_notification = true

# One profile (and one input/output alarm pair) per approved model. Confirm the
# approved model list with the customer and that each model is available in the
# account/Region before applying. Names become the `Model` cost-allocation tag.
model_sources = [
  {
    name     = "claude-sonnet-5-5"
    model_id = "us.anthropic.claude-sonnet-5-5"
    team     = "card-monroe"
  },
  {
    name     = "claude-opus-5-5"
    model_id = "us.anthropic.claude-opus-5-5"
    team     = "card-monroe"
  },
  {
    name     = "claude-haiku-5-5"
    model_id = "us.anthropic.claude-haiku-5-5"
    team     = "card-monroe"
  }
]

# CloudTrail log retention. Default is 30 days; set the customer's requirement.
# audit_log_retention_days = 365

# Only if Codex is in scope for this customer (also set allow_codex_scp_exceptions
# in management.tfvars). These feed the generated Identity Center policy.
# approved_codex_inference_profile_arns = [
#   "arn:aws:bedrock:us-east-1:<CHILD_ACCOUNT_ID>:inference-profile/global.openai.<MODEL>"
# ]
# approved_codex_project_arns = [
#   "arn:aws:bedrock:us-east-1:<CHILD_ACCOUNT_ID>:project/default"
# ]

# Record bedrock-mantle inference data events (Codex endpoint). Enable only after
# confirming the client's endpoint and that CloudTrail accepts the selector.
# enable_bedrock_mantle_data_events = true
