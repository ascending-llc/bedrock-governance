variable "region" {
  description = "AWS region for this deployment."
  type        = string
}

variable "resource_name_prefix" {
  description = "Prefix used in governance resource names."
  type        = string
}

variable "apn_id" {
  description = "AWS Partner Network ID."
  type        = string
  default     = "pc:6dk7y4gy6eblaqbh0zck484bk"
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
