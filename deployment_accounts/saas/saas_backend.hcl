# Backend config for the child-account Terraform state.
# Run: terraform init -reconfigure -backend-config=deployment_accounts/example/child_backend.hcl

# Same bucket as management_backend.hcl
bucket = "asc-bedrock-governance-terraform-states"

# Unique key for the child state
key = "bedrock-governance/saas/saas.tfstate"

region = "us-east-1"

# Same DynamoDB table as management_backend.hcl
dynamodb_table = "terraform-locks"
