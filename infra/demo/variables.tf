variable "prefix" {
  description = "Name prefix for all resources."
  type        = string
  default     = "shipyard-dev"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralus"
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
    infra             = string
    aks_nodes         = string
    private_endpoints = string
    vdi_integration   = string
    dev_vm            = string
    bastion           = string
  })

  default = {
    infra             = "10.70.0.0/24"
    aks_nodes         = "10.70.1.0/24"
    private_endpoints = "10.70.3.0/24"
    vdi_integration   = "10.70.4.0/24"
    dev_vm            = "10.70.5.0/24"
    bastion           = "10.70.6.0/26"
  }
}

variable "deploy_test_vm" {
  description = "Deploy an isolated workload VM for validating remote dev container access and tooling."
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Deploy a NAT gateway and associate it with workload subnets for outbound egress."
  type        = bool
  default     = true
}

variable "dev_vm_size" {
  description = "Azure VM size for the isolated test VM."
  type        = string
  default     = "Standard_D2as_v5"
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
  default     = "Standard_D2as_v5"
}

variable "aks_user_pool_enabled" {
  description = "Create a dedicated AKS user node pool for workload pods."
  type        = bool
  default     = true
}

variable "aks_user_pool_vm_size" {
  description = "AKS user node pool VM size."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "aks_user_pool_min_count" {
  description = "Minimum node count for AKS user node pool autoscaling."
  type        = number
  default     = 1
}

variable "aks_user_pool_max_count" {
  description = "Maximum node count for AKS user node pool autoscaling."
  type        = number
  default     = 3
}

variable "arc_bootstrap_enabled" {
  description = "Enable Terraform-orchestrated ARC bootstrap execution after AKS provisioning."
  type        = bool
  default     = false
}

variable "arc_bootstrap_execution_mode" {
  description = "Execution mode for ARC bootstrap script invocation."
  type        = string
  default     = "azure-control-plane"

  validation {
    condition     = contains(["azure-control-plane", "gitops"], var.arc_bootstrap_execution_mode)
    error_message = "arc_bootstrap_execution_mode must be one of: azure-control-plane, gitops."
  }
}

variable "arc_bootstrap_script_shell" {
  description = "Preferred shell for ARC bootstrap script invocation."
  type        = string
  default     = "bash"

  validation {
    condition     = contains(["bash", "powershell"], var.arc_bootstrap_script_shell)
    error_message = "arc_bootstrap_script_shell must be one of: bash, powershell."
  }
}

variable "arc_bootstrap_runner_scope" {
  description = "GitHub scope for ARC runners."
  type        = string
  default     = "repository"

  validation {
    condition     = contains(["repository", "organization"], var.arc_bootstrap_runner_scope)
    error_message = "arc_bootstrap_runner_scope must be one of: repository, organization."
  }
}

variable "arc_bootstrap_config_url" {
  description = "GitHub repository or organization URL used by ARC bootstrap configuration."
  type        = string
  default     = null
}

variable "arc_bootstrap_runner_labels" {
  description = "Stable labels assigned to ARC runners during bootstrap."
  type        = list(string)
  default     = ["shipyard-private", "linux", "aks"]
}

variable "arc_runner_min_replicas" {
  description = "Minimum ARC runner replicas configured during bootstrap."
  type        = number
  default     = 0

  validation {
    condition     = var.arc_runner_min_replicas >= 0
    error_message = "arc_runner_min_replicas must be >= 0."
  }
}

variable "arc_runner_max_replicas" {
  description = "Maximum ARC runner replicas configured during bootstrap."
  type        = number
  default     = 5

  validation {
    condition     = var.arc_runner_max_replicas >= var.arc_runner_min_replicas
    error_message = "arc_runner_max_replicas must be >= arc_runner_min_replicas."
  }
}

variable "arc_bootstrap_script_path_bash" {
  description = "Path to the ARC bootstrap Bash script, relative to infra/demo."
  type        = string
  default     = "../../ops/scripts/bootstrap-arc.sh"
}

variable "arc_bootstrap_script_path_powershell" {
  description = "Path to the ARC bootstrap PowerShell script, relative to infra/demo."
  type        = string
  default     = "../../ops/scripts/bootstrap-arc.ps1"
}

variable "arc_runner_nodepool_enabled" {
  description = "Create a dedicated AKS runner node pool for ARC workloads."
  type        = bool
  default     = true
}

variable "arc_runner_nodepool_name" {
  description = "Name of the dedicated ARC runner node pool."
  type        = string
  default     = "arc"
}

variable "arc_runner_nodepool_vm_size" {
  description = "VM size for the dedicated ARC runner node pool."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "arc_runner_nodepool_min_count" {
  description = "Minimum node count for dedicated ARC runner node pool autoscaling."
  type        = number
  default     = 0

  validation {
    condition     = var.arc_runner_nodepool_min_count >= 0
    error_message = "arc_runner_nodepool_min_count must be >= 0."
  }
}

variable "arc_runner_nodepool_max_count" {
  description = "Maximum node count for dedicated ARC runner node pool autoscaling."
  type        = number
  default     = 5

  validation {
    condition     = var.arc_runner_nodepool_max_count >= var.arc_runner_nodepool_min_count
    error_message = "arc_runner_nodepool_max_count must be >= arc_runner_nodepool_min_count."
  }
}

variable "arc_runner_nodepool_scale_to_zero_supported" {
  description = "Set false when selected region/SKU/cluster constraints do not support user pool min_count=0."
  type        = bool
  default     = true
}

variable "arc_runner_nodepool_labels" {
  description = "Node labels applied to the dedicated ARC runner node pool."
  type        = map(string)
  default = {
    workload = "github-runner"
  }
}

variable "arc_runner_nodepool_taints" {
  description = "Node taints applied to the dedicated ARC runner node pool."
  type        = list(string)
  default     = ["workload=github-runner:NoSchedule"]
}

variable "arc_runtime_principal_id" {
  description = "Object ID for ARC runtime identity used to assign AcrPull/AcrPush on ACR. When using the same principal as GitHub OIDC federation, use the emitted ARC_RUNTIME_PRINCIPAL_ID value from setup-github-actions scripts."
  type        = string
  default     = null
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

variable "workspace_user_group_id" {
  description = "Object ID of the Entra group for workspace users (AKS Cluster User + AcrPull + Storage File Data SMB Share Contributor)."
  type        = string
  default     = null
}

variable "workspace_operator_group_id" {
  description = "Object ID of the Entra group for Shipyard workspace operators. This group receives Key Vault Administrator, AcrPush, Azure Kubernetes Service Cluster Admin Role, and Azure Kubernetes Service RBAC Cluster Admin."
  type        = string
  default     = null
}

variable "grant_current_principal_acr_push" {
  description = "Grant AcrPush on ACR to the currently authenticated Terraform principal."
  type        = bool
  default     = true
}
