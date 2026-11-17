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

variable "break_glass_principal_arns" {
  description = <<-EOT
    IAM principal ARN patterns exempted from the Bedrock SCP deny statements (documented
    administrative / break-glass paths). Matched with ArnNotLike against aws:PrincipalArn, so use
    the role ARN without the session name. Identity Center role paths may or may not include a
    Region segment, so use a wildcard that spans both, e.g.
    "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*".
    Empty (default) means no exemption. Management mode only. Exempting a principal does not grant
    it access; it still needs an IAM allow.
  EOT
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
  description = "Days to retain CloudTrail log objects (and noncurrent versions) in the child audit bucket. Confirm the value against the customer's audit/retention requirement."
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
  description = <<-EOT
    Model IDs used to create application inference profiles and alarms in child mode.
    pricing (USD per million tokens) enables per-profile cost estimation. daily_cost_alert_usd sends
    an alert when the estimated UTC-day cost reaches it; daily_cost_limit_usd blocks the profile when
    it is reached. Both require pricing.
  EOT
  type = list(object({
    name     = string
    model_id = string
    team     = optional(string)
    pricing = optional(object({
      input_per_million       = number
      output_per_million      = number
      cache_read_per_million  = optional(number, 0)
      cache_write_per_million = optional(number, 0)
    }))
    daily_cost_limit_usd = optional(number)
    daily_cost_alert_usd = optional(number)
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

  validation {
    condition = alltrue([
      for m in var.model_sources : (m.daily_cost_limit_usd == null && m.daily_cost_alert_usd == null) || m.pricing != null
    ])
    error_message = "Each model_sources entry with daily_cost_limit_usd or daily_cost_alert_usd must set pricing."
  }

  validation {
    condition = alltrue([
      for m in var.model_sources : alltrue([
        m.daily_cost_limit_usd == null || m.daily_cost_limit_usd > 0,
        m.daily_cost_alert_usd == null || m.daily_cost_alert_usd > 0,
        m.pricing == null || (m.pricing.input_per_million >= 0 && m.pricing.output_per_million >= 0 && m.pricing.cache_read_per_million >= 0 && m.pricing.cache_write_per_million >= 0)
      ])
    ])
    error_message = "Cost limits and alert thresholds must be greater than zero, and token prices must not be negative."
  }
}

variable "cost_alert_threshold_percent" {
  description = "Percent of daily_cost_limit_usd at which a cost alert fires for profiles that set a limit but no explicit daily_cost_alert_usd."
  type        = number
  default     = 80

  validation {
    condition     = var.cost_alert_threshold_percent > 0 && var.cost_alert_threshold_percent <= 100
    error_message = "cost_alert_threshold_percent must be greater than 0 and at most 100."
  }
}

variable "enforce_daily_cost_limits" {
  description = "When true (default), profiles that reach daily_cost_limit_usd are denied through the cost-limit block policy. When false the limit is only reported (CostLimitBlocked metric and alarm), which is useful as a dry run."
  type        = bool
  default     = true
}

variable "cost_check_interval_minutes" {
  description = "How often the cost enforcer Lambda runs. Bedrock metrics lag by a few minutes, so values below 5 add little."
  type        = number
  default     = 5

  validation {
    condition     = var.cost_check_interval_minutes >= 1 && var.cost_check_interval_minutes <= 60 && floor(var.cost_check_interval_minutes) == var.cost_check_interval_minutes
    error_message = "cost_check_interval_minutes must be a whole number between 1 and 60."
  }
}

variable "cost_limit_block_policy_role_names" {
  description = "Names of IAM roles to attach the cost-limit block policy to. Leave empty when the policy is referenced from IAM Identity Center permission sets as a customer managed policy instead."
  type        = list(string)
  default     = []
}
