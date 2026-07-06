# Backend config for the child-account Terraform state.
# Run: terraform init -reconfigure -backend-config=deployment_accounts/example/child_backend.hcl

# Same bucket as management_backend.hcl
bucket = "<STATE_BUCKET_NAME>"

# Unique key for the child state
key = "bedrock-governance/child.tfstate"

region = "<AWS_REGION>"

# Same DynamoDB table as management_backend.hcl
dynamodb_table = "<LOCK_TABLE_NAME>"
