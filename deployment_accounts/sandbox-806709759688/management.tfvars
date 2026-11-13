# Management-account deployment for the isolated sandbox test.
region               = "us-east-1"
resource_name_prefix = "bg-sbx-806709759688"
deployment_mode      = "management"

# Attach the SCP to the sandbox member account only. Do not change to an OU or root.
scp_target_ids = ["806709759688"]

# Strict mode requires exact AIP ARNs created by the child deployment. Populate
# this list from the child state's `terraform output -json inference_profile_arns`
# before planning the management state.
enforce_approved_application_inference_profiles = true
approved_application_inference_profile_arns     = []

# No additional direct foundation-model pattern exceptions.
direct_access_model_id_patterns = []

# Activate billing tags after the child AIPs with these keys have been created.
cost_allocation_tag_keys = ["Project", "Team"]