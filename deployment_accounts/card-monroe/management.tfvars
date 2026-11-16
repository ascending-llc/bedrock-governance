# Management-account deployment (SCP) for the Card Monroe POC.
# Replace every <PLACEHOLDER> before planning; see README.md in this folder.
region               = "us-east-1"
resource_name_prefix = "bg-cm-<CHILD_ACCOUNT_ID>"
deployment_mode      = "management"

# Attach to the POC account only. Move to an OU only after the POC is accepted.
scp_target_ids = ["<CHILD_ACCOUNT_ID>"]

# Strict mode allows only the exact profile ARNs below. Populate them from the
# child state's `terraform output -json inference_profile_arns` before planning.
enforce_approved_application_inference_profiles = true
approved_application_inference_profile_arns = [
  "arn:aws:bedrock:us-east-1:<CHILD_ACCOUNT_ID>:application-inference-profile/<SONNET_PROFILE_ID>",
  "arn:aws:bedrock:us-east-1:<CHILD_ACCOUNT_ID>:application-inference-profile/<OPUS_PROFILE_ID>",
  "arn:aws:bedrock:us-east-1:<CHILD_ACCOUNT_ID>:application-inference-profile/<HAIKU_PROFILE_ID>",
]

direct_access_model_id_patterns = []

# Block the bedrock-mantle endpoint so clients cannot bypass the profile controls.
deny_bedrock_mantle_inference = true

# Codex exemptions (global.openai.* profiles and project/default) are OFF for this
# customer. Set true only if Codex is in scope and the customer approves.
allow_codex_scp_exceptions = false

# Activate after the child profiles carrying these tags exist and have usage
# (billing can take about a day to recognize a new tag).
cost_allocation_tag_keys = ["Project", "Team", "Model"]

# Optional documented break-glass path; does not grant access by itself.
# See docs/scp-break-glass.md.
# break_glass_principal_arns = [
#   "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"
# ]
