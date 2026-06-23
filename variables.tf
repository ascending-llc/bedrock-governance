variable "region" {
  description = "AWS region for this deployment."
  type        = string
}

variable "resource_name_prefix" {
  description = "Prefix used in governance resource names."
  type        = string
}

variable "deploy_role_arn" {
  description = "Optional IAM role ARN for provider-side deployments (assumed after backend auth)."
  type        = string
  default     = null
}

variable "deploy_role_session_name" {
  description = "STS session name used when assume_role is enabled for deployments."
  type        = string
  default     = "bedrock-governance-terraform"
}

variable "deployment_mode" {
  description = "Deploy child resources or management SCP resources."
  type        = string
  default     = "child"

  validation {
    condition     = contains(["child", "management"], var.deployment_mode)
    error_message = "deployment_mode must be child or management."
  }
}

variable "scp_target_ids" {
  description = "Organizations account and/or OU IDs where SCP should be attached."
  type        = list(string)
  default     = []
}

variable "model_sources" {
  description = "Model IDs used to create application inference profiles and related alarm behavior in child mode."
  type = list(object({
    name     = string
    model_id = string
  }))
  default = []

  validation {
    condition     = alltrue([for m in var.model_sources : length(trimspace(m.model_id)) > 0])
    error_message = "Each model_sources item must have a non-empty model_id."
  }
}
