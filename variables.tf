variable "region" {
  description = "AWS region for this deployment."
  type        = string
}

variable "resource_name_prefix" {
  description = "Prefix used in governance resource names."
  type        = string
}

variable "alarm_email" {
  description = "Optional email address to notify when an anomaly alarm transitions to ALARM or OK."
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

variable "break_glass_principal_arns" {
  description = "IAM principal ARN patterns exempted from the Bedrock SCP deny statements (documented administrative / break-glass paths). Management mode only; empty means no exemption."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.break_glass_principal_arns : can(regex("^arn:aws[^:]*:iam::([0-9]{12}|\\*):(role|user)/.+$", arn))
    ])
    error_message = "Each break-glass principal must be an IAM role or user ARN pattern (arn:aws:iam::<account-id or *>:role/...)."
  }

  validation {
    condition     = var.deployment_mode == "management" || length(var.break_glass_principal_arns) == 0
    error_message = "break_glass_principal_arns only applies to the SCP in management mode."
  }
}

variable "audit_log_retention_days" {
  description = "Days to retain CloudTrail log objects and noncurrent versions in the child audit bucket."
  type        = number
  default     = 30

  validation {
    condition     = var.audit_log_retention_days >= 30 && floor(var.audit_log_retention_days) == var.audit_log_retention_days
    error_message = "audit_log_retention_days must be a whole number of at least 30."
  }
}

variable "allow_codex_scp_exceptions" {
  description = "Exempt the global.openai.* system inference profiles and project/default from the Bedrock SCP so Codex can work without an application inference profile. Defaults to true to preserve existing deployments; set false where Codex is not in scope."
  type        = bool
  default     = true
}

variable "enable_bedrock_mantle_data_events" {
  description = "Also record bedrock-mantle inference data events (AWS::BedrockMantle::Project), used by OpenAI-compatible clients such as Codex. Enable only after confirming the client's endpoint and that CloudTrail accepts the selector."
  type        = bool
  default     = false
}

variable "deny_bedrock_mantle_inference" {
  description = "Add an SCP statement denying bedrock-mantle:CreateInference (except for break_glass_principal_arns), so clients cannot bypass the approved-profile controls through the bedrock-mantle endpoint. Management mode only."
  type        = bool
  default     = false
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
    error_message = "Each approved application inference profile must be an exact ARN without wildcard characters."
  }
}

variable "enforce_approved_application_inference_profiles" {
  description = "When true, the SCP allows only the exact application inference profile ARNs in approved_application_inference_profile_arns."
  type        = bool
  default     = false
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
    error_message = "Each approved Codex inference profile must be an exact ARN without wildcard characters."
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
    error_message = "Each approved Codex project must be an exact Bedrock project ARN without wildcard characters."
  }
}

variable "direct_access_model_id_patterns" {
  description = "Foundation model ID glob patterns exempted from the AIP requirement and allowed to be invoked directly."
  type        = list(string)
  default     = []
}

variable "cost_allocation_tag_keys" {
  description = "Cost allocation tag keys to activate in the management account."
  type        = set(string)
  default     = []
}

variable "model_sources" {
  description = "Model IDs used to create application inference profiles and related alarm behavior in child mode. Use one entry per team per model to enable per-team usage tracking."
  type = list(object({
    name     = string
    model_id = string
    team     = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for m in var.model_sources : length(trimspace(m.model_id)) > 0])
    error_message = "Each model_sources item must have a non-empty model_id."
  }

  validation {
    condition     = alltrue([for m in var.model_sources : m.team == null || length(trimspace(m.team)) > 0])
    error_message = "Each model_sources item with a team must have a non-empty team value."
  }
}
