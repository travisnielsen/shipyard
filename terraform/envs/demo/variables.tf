variable "prefix" {
  description = "Name prefix for all resources."
  type        = string
  default     = "shipyard-dev"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
  default     = "rg-shipyard-dev"
}

variable "deploy_targets" {
  description = "Targets to deploy: aks, container_apps, or both."
  type        = set(string)
  default     = ["aks", "container_apps"]

  validation {
    condition     = length(setsubtract(var.deploy_targets, ["aks", "container_apps"])) == 0
    error_message = "deploy_targets may only include 'aks' and/or 'container_apps'."
  }
}

variable "vnet_cidr" {
  description = "VNet address space."
  type        = string
  default     = "10.70.0.0/16"
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs for private topology segments."
  type = object({
    infra              = string
    aks_nodes          = string
    container_apps_env = string
    private_endpoints  = string
    vdi_integration    = string
  })

  default = {
    infra              = "10.70.0.0/24"
    aks_nodes          = "10.70.1.0/24"
    container_apps_env = "10.70.2.0/24"
    private_endpoints  = "10.70.3.0/24"
    vdi_integration    = "10.70.4.0/24"
  }
}

variable "aks_node_count" {
  description = "Initial AKS node count."
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "AKS node pool VM size."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "container_app_image" {
  description = "Container image for the demo remote workspace app in ACA."
  type        = string
  default     = "mcr.microsoft.com/devcontainers/base:ubuntu"
}

variable "tags" {
  description = "Common tags applied to resources."
  type        = map(string)
  default = {
    environment = "demo"
    managedBy   = "terraform"
    workload    = "remote-devcontainer"
  }
}
