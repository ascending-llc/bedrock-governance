region               = "us-east-1"
resource_name_prefix = "bedrock-governance-mgmt"
deployment_mode      = "management"

scp_target_ids                  = ["897729109735"]
direct_access_model_id_patterns = ["amazon.titan-*", "cohere.rerank-*"]