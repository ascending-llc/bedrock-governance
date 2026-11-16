# Management state backend. Bucket and table come from the management bootstrap stack.
bucket         = "<STATE_BUCKET_NAME>"
key            = "bedrock-governance/card-monroe/management.tfstate"
region         = "us-east-1"
dynamodb_table = "<LOCK_TABLE_NAME>"
