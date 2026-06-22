variable "resource_name_prefix" {
  description = "Prefix used in governance resource names."
  type        = string
}

variable "apn_id" {
  description = "AWS Partner Network ID for tagging."
  type        = string
  default     = "pc:6dk7y4gy6eblaqbh0zck484bk"
}

variable "deployment_mode" {
  description = "Deploy child resources or management SCP resources."
  type        = string
}

variable "scp_target_ids" {
  description = "Organizations account and/or OU IDs where SCP should be attached."
  type        = list(string)
}

variable "model_sources" {
  description = "Model IDs used to create application inference profiles and alarms in child mode."
  type = list(object({
    name     = string
    model_id = string
  }))
}
