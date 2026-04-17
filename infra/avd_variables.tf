variable "deploy_avd" {
  description = "Feature flag to deploy Azure Virtual Desktop resources."
  type        = bool
  default     = false
}

variable "avd_users_entra_group_id" {
  description = "Object ID for the Entra ID group granted Desktop Virtualization User access."
  type        = string
  default     = ""

  validation {
    condition = (
      var.avd_users_entra_group_id == "" ||
      can(regex("^[0-9a-fA-F-]{36}$", var.avd_users_entra_group_id))
    )
    error_message = "avd_users_entra_group_id must be empty or a valid GUID."
  }

  validation {
    condition     = !var.deploy_avd || length(trimspace(var.avd_users_entra_group_id)) > 0
    error_message = "avd_users_entra_group_id is required when deploy_avd is true."
  }
}

variable "avd_session_host_count" {
  description = "Number of AVD session host VMs to deploy."
  type        = number
  default     = 1

  validation {
    condition     = var.avd_session_host_count >= 1
    error_message = "avd_session_host_count must be >= 1."
  }
}

variable "avd_session_host_sku" {
  description = "VM size for session hosts."
  type        = string
  default     = "Standard_D2s_v5"

  validation {
    condition = contains([
      "Standard_D2s_v5",
      "Standard_D2as_v5",
      "Standard_B2ms",
    ], var.avd_session_host_sku)
    error_message = "avd_session_host_sku must be one of Standard_D2s_v5, Standard_D2as_v5, or Standard_B2ms."
  }
}
