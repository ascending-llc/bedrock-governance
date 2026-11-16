# Child state backend. Uses the management-account state bucket created by
# bootstrap/management_bootstrap.yaml (same bucket as management_backend.hcl).
bucket         = "<STATE_BUCKET_NAME>"
key            = "bedrock-governance/card-monroe/child.tfstate"
region         = "us-east-1"
dynamodb_table = "<LOCK_TABLE_NAME>"
