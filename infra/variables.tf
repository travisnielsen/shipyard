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
    acr_tasks         = string
    private_endpoints = string
    vdi_integration   = string
    dev_vm            = string
    bastion           = string
  })

  default = {
    infra             = "10.70.0.0/24"
    aks_nodes         = "10.70.1.0/24"
    acr_tasks         = "10.70.2.0/27"
    private_endpoints = "10.70.3.0/24"
    vdi_integration   = "10.70.4.0/24"
    dev_vm            = "10.70.5.0/24"
    bastion           = "10.70.6.0/26"
  }
}

variable "enable_private_acr_tasks" {
  description = "Deploy a private, VNET-injected ACR Task agent pool for image builds."
  type        = bool
  default     = true
}

variable "acr_task_agentpool_name" {
  description = "Name of the private ACR Task agent pool."
  type        = string
  default     = "arcbuild"
}

variable "acr_task_agentpool_tier" {
  description = "SKU tier for the ACR Task agent pool."
  type        = string
  default     = "S2"

  validation {
    condition     = contains(["S1", "S2", "S3"], var.acr_task_agentpool_tier)
    error_message = "acr_task_agentpool_tier must be one of: S1, S2, S3."
  }
}

variable "acr_task_agentpool_instance_count" {
  description = "Number of agents in the private ACR Task agent pool."
  type        = number
  default     = 1

  validation {
    condition     = var.acr_task_agentpool_instance_count >= 1
    error_message = "acr_task_agentpool_instance_count must be >= 1."
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

variable "arc_github_app_id" {
  description = "GitHub App ID used by ARC runner scale set authentication."
  type        = string
  default     = null
}

variable "arc_github_app_installation_id" {
  description = "GitHub App Installation ID used by ARC runner scale set authentication."
  type        = string
  default     = null
}

variable "arc_github_app_private_key_path" {
  description = "Path to GitHub App private key (.pem) used to create ARC auth secret, relative to infra or absolute."
  type        = string
  default     = null
}

variable "arc_bootstrap_runner_labels" {
  description = "Stable labels assigned to ARC runners during bootstrap."
  type        = list(string)
  default     = ["shipyard-private", "linux", "aks"]
}

variable "arc_runner_image" {
  description = "Container image URI for ARC runner pods. Override with custom image from ACR (e.g., shipyardXXXXacr.azurecr.io/actions-runner:latest)."
  type        = string
  default     = "ghcr.io/actions/actions-runner:latest"
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
  description = "Path to the ARC bootstrap Bash script, relative to infra."
  type        = string
  default     = "scripts/bootstrap-arc.sh"
}

variable "arc_bootstrap_script_path_powershell" {
  description = "Path to the ARC bootstrap PowerShell script, relative to infra."
  type        = string
  default     = "scripts/bootstrap-arc.ps1"
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

variable "github_oidc_principal_id" {
  description = "Object ID for GitHub Actions OIDC federated identity. If not provided, defaults to arc_runtime_principal_id. Used to assign AcrPull/AcrPush permissions on ACR for GitHub Actions workflows."
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

# ============================================================================
# Managed Egress via Azure Firewall Configuration (T004-T006)
# ============================================================================

variable "managed_egress_enabled" {
  description = "Enable managed egress mode via Azure Firewall in a dedicated hub VNet. Mutually exclusive with enable_nat_gateway."
  type        = bool
  default     = false
}

variable "managed_egress_firewall_sku" {
  description = "Azure Firewall SKU for managed egress mode. Standard supports DNS/FQDN filtering; Premium supports TLS inspection and advanced threat intelligence."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.managed_egress_firewall_sku)
    error_message = "managed_egress_firewall_sku must be 'Standard' or 'Premium'."
  }
}

variable "managed_egress_hub_vnet_cidr" {
  description = "CIDR block for the dedicated managed egress hub VNet. Must not overlap with vnet_cidr."
  type        = string
  default     = "10.80.0.0/16"

  validation {
    condition     = can(cidrhost(var.managed_egress_hub_vnet_cidr, 0))
    error_message = "managed_egress_hub_vnet_cidr must be a valid CIDR block."
  }
}

variable "managed_egress_hub_subnet_cidrs" {
  description = "Subnet CIDRs for the managed egress hub VNet. Must include 'azure_firewall' subnet."
  type = object({
    azure_firewall = string
  })
  default = {
    azure_firewall = "10.80.0.0/26"
  }

  validation {
    condition     = can(cidrhost(var.managed_egress_hub_subnet_cidrs.azure_firewall, 0))
    error_message = "All subnet CIDRs must be valid CIDR blocks."
  }
}

variable "managed_egress_allow_fqdns" {
  description = "List of fully qualified domain names (FQDNs) to allow in managed egress outbound policy. Duplicate entries are not permitted."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.managed_egress_allow_fqdns) == length(distinct(var.managed_egress_allow_fqdns))
    error_message = "managed_egress_allow_fqdns must not contain duplicate values."
  }
}

variable "managed_egress_allow_ip_destinations" {
  description = "List of IP addresses or CIDR blocks to allow in managed egress outbound policy (optional, for non-FQDN traffic)."
  type        = list(string)
  default     = []
}

variable "managed_egress_required_platform_fqdns" {
  description = "Baseline platform dependency FQDNs that must remain reachable in managed egress mode. These are auto-merged into the effective allow-list."
  type        = list(string)
  default = [
    "management.azure.com",
    "login.microsoftonline.com",
    "mcr.microsoft.com"
  ]
}

# ============================================================================
# FIREWALL POLICY & CAPABILITY VALIDATION (T024-T026)
# ============================================================================

variable "managed_egress_firewall_policy_name" {
  description = "Name for the Azure Firewall policy resource. Only used in managed egress mode."
  type        = string
  default     = ""
}

variable "managed_egress_enable_dns_proxy" {
  description = "Enable DNS proxy on the firewall for FQDN-based filtering. Required for proper DNS interception."
  type        = bool
  default     = true
}

variable "managed_egress_default_rule_action" {
  description = "Default fallback firewall action in managed egress mode. Use 'Allow' for initial allow-by-default posture, or 'Deny' for strict allow-list enforcement."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.managed_egress_default_rule_action)
    error_message = "managed_egress_default_rule_action must be 'Allow' or 'Deny'."
  }
}

# Firewall SKU capability validation is implicit:
# - Standard SKU: Supports DNS/FQDN filtering via firewall policy application rules
# - Premium SKU: Includes Standard + TLS inspection, threat intelligence, URL filtering
# If TLS inspection features are needed later, upgrade SKU from Standard to Premium
# and update the firewall policy rules to include inspection rules.


