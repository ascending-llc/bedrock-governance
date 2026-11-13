# Dedicated state key in the existing governance backend.
# Verify this bucket/table are in the management account and approved for reuse.
bucket         = "asc-bedrock-governance-terraform-states"
key            = "bedrock-governance/sandbox-806709759688/management.tfstate"
region         = "us-east-1"
use_lockfile   = true