# Dedicated child state key; backend access uses management-account credentials.
# The AWS provider assumes BedrockGovernanceDeployer in account 806709759688.
bucket         = "asc-bedrock-governance-terraform-states"
key            = "bedrock-governance/sandbox-806709759688/child.tfstate"
region         = "us-east-1"
use_lockfile   = true