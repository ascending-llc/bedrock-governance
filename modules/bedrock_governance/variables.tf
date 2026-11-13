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

variable "approved_application_inference_profile_arns" {
  description = "Exact application inference profile ARNs allowed by the SCP when strict profile enforcement is enabled."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.approved_application_inference_profile_arns : can(regex(
        "^arn:aws[^:]*:bedrock:[^:*?]+:[0-9]{12}:application-inference-profile/[^*?]+$",
        arn
      ))
    ])
    error_message = "Each approved application inference profile must be an exact application-inference-profile ARN."
  }
}

variable "enforce_approved_application_inference_profiles" {
  description = "When true, the SCP allows only the exact application inference profile ARNs in approved_application_inference_profile_arns."
  type        = bool
  default     = false

  validation {
    condition = !var.enforce_approved_application_inference_profiles || (
      var.deployment_mode == "management" && length(var.approved_application_inference_profile_arns) > 0
    )
    error_message = "Strict application inference profile enforcement requires management mode and at least one approved profile ARN."
  }
}

variable "approved_codex_inference_profile_arns" {
  description = "Exact Codex system inference profile ARNs included in the generated Identity Center permission policy."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.approved_codex_inference_profile_arns : can(regex(
        "^arn:aws[^:]*:bedrock:[^:*?]+:[0-9]{12}:inference-profile/[^*?]+$",
        arn
      ))
    ])
    error_message = "Each approved Codex inference profile must be an exact inference-profile ARN."
  }
}

variable "approved_codex_project_arns" {
  description = "Exact Codex project ARNs included in the generated Identity Center permission policy."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.approved_codex_project_arns : can(regex(
        "^arn:aws[^:]*:bedrock:[^:*?]+:[0-9]{12}:project/[^*?]+$",
        arn
      ))
    ])
    error_message = "Each approved Codex project must be an exact Bedrock project ARN."
  }
}

variable "direct_access_model_id_patterns" {
  description = "Foundation model ID glob patterns (e.g. \"amazon.titan-*\") exempted from the AIP requirement and allowed to be invoked directly."
  type        = list(string)
  default     = []
}

variable "alarm_email" {
  description = "Optional email address to notify when an anomaly alarm transitions to ALARM or OK. If set, an SNS topic and email subscription are created automatically."
  type        = string
  default     = null
}

variable "alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN for anomaly alarm notifications. Mutually exclusive with alarm_email."
  type        = string
  default     = null

  validation {
    condition     = var.alarm_sns_topic_arn == null || can(regex("^arn:aws[^:]*:sns:[^:]+:[0-9]{12}:.+$", var.alarm_sns_topic_arn))
    error_message = "alarm_sns_topic_arn must be an SNS topic ARN."
  }

  validation {
    condition     = var.alarm_email == null || var.alarm_sns_topic_arn == null
    error_message = "Set at most one of alarm_email and alarm_sns_topic_arn."
  }
}

variable "require_alarm_notification" {
  description = "Require exactly one anomaly notification target for child deployments."
  type        = bool
  default     = false

  validation {
    condition = !var.require_alarm_notification || (
      var.deployment_mode == "child" && ((var.alarm_email != null) != (var.alarm_sns_topic_arn != null))
    )
    error_message = "When require_alarm_notification is true in child mode, set exactly one of alarm_email or alarm_sns_topic_arn."
  }
}

variable "cost_allocation_tag_keys" {
  description = "Cost allocation tag keys to activate in the management account. Child resources must carry these tags before activation."
  type        = set(string)
  default     = []

  validation {
    condition     = var.deployment_mode == "management" || length(var.cost_allocation_tag_keys) == 0
    error_message = "Cost allocation tag activation is only available in management mode."
  }
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
    condition     = alltrue([for m in var.model_sources : length(trimspace(m.name)) > 0])
    error_message = "Each model_sources entry must have a non-empty name."
  }

  validation {
    condition     = alltrue([for m in var.model_sources : m.team == null || length(trimspace(m.team)) > 0])
    error_message = "Each model_sources entry with a team must have a non-empty team value."
  }
}
