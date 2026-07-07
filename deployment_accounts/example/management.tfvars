# Variables for the management-account deployment (SCP).
# Apply with: terraform apply -var-file=deployment_accounts/example/management.tfvars

region               = "<AWS_REGION>"           # e.g. "us-east-1"
resource_name_prefix = "<RESOURCE_NAME_PREFIX>" # e.g. "bedrock-governance"
deployment_mode      = "management"

# Account IDs or OU IDs to attach the SCP to.
# Find account IDs in AWS Organizations > Accounts.
# Find OU IDs in AWS Organizations > AWS accounts (select an OU, copy its ID).
scp_target_ids = ["<ACCOUNT_ID_OR_OU_ID>"]

# Foundation model ID glob patterns exempted from the AIP requirement.
direct_access_model_id_patterns = ["<MODEL_ID_PATTERN>"] # e.g. "amazon.titan-*"
