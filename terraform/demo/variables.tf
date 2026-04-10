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
    private_endpoints  = string
    vdi_integration    = string
    dev_vm        = string
    bastion            = string
  })

  default = {
    infra              = "10.70.0.0/24"
    aks_nodes          = "10.70.1.0/24"
    private_endpoints  = "10.70.3.0/24"
    vdi_integration    = "10.70.4.0/24"
    dev_vm        = "10.70.5.0/24"
    bastion            = "10.70.6.0/26"
  }
}

variable "deploy_test_vm" {
  description = "Deploy an isolated workload VM for validating remote dev container access and tooling."
  type        = bool
  default     = true
}

variable "dev_vm_size" {
  description = "Azure VM size for the isolated test VM."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "dev_vm_admin_username" {
  description = "Admin username for the isolated test VM."
  type        = string
  default     = "azureuser"
}

variable "dev_vm_admin_password" {
  description = "Admin password for the isolated Windows test VM (used for Bastion RDP login)."
  type        = string
  sensitive   = true
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

variable "tags" {
  description = "Common tags applied to resources."
  type        = map(string)
  default = {
    environment = "demo"
    managedBy   = "terraform"
    workload    = "remote-devcontainer"
  }
}

variable "platform_admins_group_id" {
  description = "Object ID of the Entra group that receives platform admin privileges (Key Vault Administrator, AcrPush)."
  type        = string
  default     = null
}

variable "dev_group_id" {
  description = "Object ID of the Entra group that receives developer access (AKS Cluster User, AcrPull)."
  type        = string
  default     = null
}

variable "grant_current_principal_acr_push" {
  description = "Grant AcrPush on ACR to the currently authenticated Terraform principal."
  type        = bool
  default     = true
}
