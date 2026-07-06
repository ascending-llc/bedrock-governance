# Backend config for the management-account Terraform state.
# Run: terraform init -reconfigure -backend-config=deployment_accounts/<your-account>/management_backend.hcl

# S3BucketName output from management_bootstrap.yaml CloudFormation stack
bucket = "<STATE_BUCKET_NAME>"

# Unique key for the management state
key = "bedrock-governance/management.tfstate"

region = "<AWS_REGION>"

# DynamoDBTableName output from management_bootstrap.yaml CloudFormation stack
dynamodb_table = "<LOCK_TABLE_NAME>"
