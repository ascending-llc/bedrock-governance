variable "resource_name_prefix" {
  description = "Prefix used in governance resource names."
  type        = string
}

variable "deployment_mode" {
  description = "Deploy child resources or management SCP resources."
  type        = string

  validation {
    condition     = contains(["child", "management"], var.deployment_mode)
    error_message = "deployment_mode must be child or management."
  }
}

variable "scp_target_ids" {
  description = "Organizations account and/or OU IDs where SCP should be attached."
  type        = list(string)
}

variable "alarm_email" {
  description = "Optional email address to notify when an anomaly alarm transitions to ALARM or OK. If set, an SNS topic and email subscription are created automatically."
  type        = string
  default     = null
}

variable "model_sources" {
  description = "Model IDs used to create application inference profiles and alarms in child mode."
  type = list(object({
    name     = string
    model_id = string
    team     = optional(string)
  }))

  validation {
    condition     = alltrue([for m in var.model_sources : length(trimspace(m.model_id)) > 0])
    error_message = "Each model_sources entry must have a non-empty model_id."
  }

  validation {
    condition     = alltrue([for m in var.model_sources : length(trimspace(m.model_name)) > 0])
    error_message = "Each model_sources entry must have a non-empty model_name."
  }

  validation {
    condition     = alltrue([for m in var.model_sources : m.team == null || length(trimspace(m.team)) > 0])
    error_message = "Each model_sources entry with a team must have a non-empty team value."
  }
}
