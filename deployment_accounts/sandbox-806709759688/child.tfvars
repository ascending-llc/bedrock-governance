# Child-account deployment for the isolated sandbox test.
region               = "us-east-1"
resource_name_prefix = "bg-sbx-806709759688"
deployment_mode      = "child"

# Bootstrap this role in account 806709759688 before Terraform deployment.
# Its trust must be scoped to the approved management-account deployment role.
deploy_role_arn = "arn:aws:iam::806709759688:role/BedrockGovernanceDeployer"

# POC anomaly-alarm notification recipient.
alarm_email                = "reagan.allen@ascendingdc.com"
require_alarm_notification = true

# Candidate Claude models copied from the SaaS configuration. Confirm model approval,
# agreement availability and sandbox inference access before applying.
model_sources = [
  {
    name     = "claude-sonnet-5-5"
    model_id = "us.anthropic.claude-sonnet-5-5"
    team     = "sandbox"
  },
  {
    name     = "claude-opus-5-5"
    model_id = "us.anthropic.claude-opus-5-5"
    team     = "sandbox"
  },
  {
    name     = "claude-haiku-5-5"
    model_id = "us.anthropic.claude-haiku-5-5"
    team     = "sandbox"
  }
]

# Codex inference remains on the existing system-profile / default-project path.
# These exact ARNs constrain the generated Identity Center policy to the models
# approved in the SaaS configuration; adjust only after customer model approval.
approved_codex_inference_profile_arns = [
  "arn:aws:bedrock:us-east-1:806709759688:inference-profile/us.openai.gpt-6.1-sol",
  "arn:aws:bedrock:us-east-1:806709759688:inference-profile/us.openai.gpt-6.1-terra",
  "arn:aws:bedrock:us-east-1:806709759688:inference-profile/us.openai.gpt-6-luna"
]

approved_codex_project_arns = [
  "arn:aws:bedrock:us-east-1:806709759688:project/default"
]