# ---------------------------------------------------------------------------
# Identity / RBAC baselines
# ---------------------------------------------------------------------------
# Centralized role assignment management for all service and human principals.
# Grouped by recipient type: workload identities, Azure service principals,
# human groups (operators/users), and CI/CD runtime identities.

# ============================================================================
# AKS Workload Identity Permissions
# ============================================================================
# The AKS cluster's managed identities (kubelet and control-plane) need
# permissions to pull images and interact with Azure Files for workspace storage.

resource "azurerm_role_assignment" "aks_acr_pull" {
  count = local.deploy_aks ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPull"
  principal_id = coalesce(
    try(module.aks[0].kubelet_identity.object_id, null),
    try(module.aks[0].kubelet_identity.objectId, null)
  )
}

resource "azurerm_role_assignment" "aks_storage_file_mi_admin" {
  count = local.deploy_aks ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage File Data SMB MI Admin"
  principal_id = coalesce(
    try(module.aks[0].kubelet_identity.object_id, null),
    try(module.aks[0].kubelet_identity.objectId, null)
  )
}

resource "azurerm_role_assignment" "aks_storage_account_contributor" {
  count = local.deploy_aks ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Account Contributor"
  principal_id = coalesce(
    try(module.aks[0].identity_principal_id, null),
    try(module.aks[0].kubelet_identity.object_id, null),
    try(module.aks[0].kubelet_identity.objectId, null)
  )
}

resource "azurerm_role_assignment" "aks_cluster_storage_file_contributor" {
  count = local.deploy_aks && try(module.aks[0].identity_principal_id, null) != null ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = module.aks[0].identity_principal_id
}

# ============================================================================
# AVD Azure Service Principal Permissions
# ============================================================================
# Azure Virtual Desktop service principal needs permission to manage session
# host power states and user login assignments.

# Operator permission to manage AVD credentials in the dedicated Key Vault.
resource "azurerm_role_assignment" "avd_keyvault_secrets_officer" {
  count = var.deploy_avd ? 1 : 0

  scope                = module.avd_key_vault[0].resource_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure Virtual Desktop first-party service principal (9cdead84-a844-4324-93f2-b2e6bb768d07)
# needs Desktop Virtualization Power On Contributor to support start_vm_on_connect behavior.
resource "azurerm_role_assignment" "avd_power_on_contributor" {
  count = var.deploy_avd ? 1 : 0

  scope                = azurerm_resource_group.this.id
  role_definition_name = "Desktop Virtualization Power On Contributor"
  principal_id         = "c593113c-48df-45ed-8fbb-74e301fc67df" # Azure Virtual Desktop SP
  principal_type       = "ServicePrincipal"
}

# Workspace users access to AVD session hosts (enumerated via local.avd_session_hosts).
resource "azurerm_role_assignment" "avd_vm_user_login" {
  for_each = local.avd_session_hosts

  scope                = module.avd_session_host[each.key].resource_id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.avd_users_entra_group_id
  principal_type       = "Group"
}

# ============================================================================
# Workspace Operator Permissions
# ============================================================================
# Operators maintain infrastructure and pipelines: admin access to Key Vault,
# ability to push images, and AKS cluster administration via RBAC.

resource "azurerm_role_assignment" "workspace_operators_kv_admin" {
  count = var.workspace_operator_group_id != null ? 1 : 0

  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.workspace_operator_group_id
}

resource "azurerm_role_assignment" "workspace_operators_acr_push" {
  count = var.workspace_operator_group_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPush"
  principal_id         = var.workspace_operator_group_id
}

resource "azurerm_role_assignment" "workspace_operators_aks_rbac_cluster_admin" {
  count = local.deploy_aks && var.workspace_operator_group_id != null ? 1 : 0

  scope                = module.aks[0].resource_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.workspace_operator_group_id
}

resource "azurerm_role_assignment" "workspace_operators_aks_cluster_admin" {
  count = local.deploy_aks && var.workspace_operator_group_id != null ? 1 : 0

  scope                = module.aks[0].resource_id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = var.workspace_operator_group_id
}

# ============================================================================
# Workspace User Permissions
# ============================================================================
# Users pull container images and access workspace storage (Azure Files).

resource "azurerm_role_assignment" "workspace_user_acr_pull" {
  count = var.workspace_user_group_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPull"
  principal_id         = var.workspace_user_group_id
}

resource "azurerm_role_assignment" "workspace_user_aks_user" {
  count = local.deploy_aks && var.workspace_user_group_id != null ? 1 : 0

  scope                = module.aks[0].resource_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.workspace_user_group_id
}

resource "azurerm_role_assignment" "workspace_user_storage_file_contributor" {
  count = var.workspace_user_group_id != null ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.workspace_user_group_id
}

# ============================================================================
# Current Principal (Elevated Self-Access)
# ============================================================================
# Optional elevated permissions for the operator running Terraform.

resource "azurerm_role_assignment" "current_principal_acr_push" {
  count = var.grant_current_principal_acr_push ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================================================
# ARC Runtime Identity Permissions
# ============================================================================
# ARC-deployed GitHub Actions runners need to pull images, read metadata,
# push images, and manage ACR build tasks.

resource "azurerm_role_assignment" "arc_runtime_acr_pull" {
  count = var.arc_runtime_principal_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPull"
  principal_id         = var.arc_runtime_principal_id
}

resource "azurerm_role_assignment" "arc_runtime_acr_reader" {
  count = var.arc_runtime_principal_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "Reader"
  principal_id         = var.arc_runtime_principal_id
}

resource "azurerm_role_assignment" "arc_runtime_acr_push" {
  count = var.arc_runtime_principal_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPush"
  principal_id         = var.arc_runtime_principal_id
}

resource "azurerm_role_assignment" "arc_runtime_acr_tasks_contributor" {
  count = var.arc_runtime_principal_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "Container Registry Tasks Contributor"
  principal_id         = var.arc_runtime_principal_id
}

# ============================================================================
# GitHub Actions OIDC Identity Permissions
# ============================================================================
# Optional: separate federated identity for GitHub Actions workflows.
# Only creates distinct assignments if OIDC principal differs from ARC runtime.

locals {
  github_oidc_principal_id = var.github_oidc_principal_id != null ? var.github_oidc_principal_id : var.arc_runtime_principal_id
  # Only create separate assignments if the principals are different.
  # Otherwise, the arc_runtime assignments above already cover the permissions.
  create_separate_github_oidc_assignments = (
    var.github_oidc_principal_id != null &&
    var.github_oidc_principal_id != var.arc_runtime_principal_id
  )
}

resource "azurerm_role_assignment" "github_oidc_acr_pull" {
  count = local.create_separate_github_oidc_assignments ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPull"
  principal_id         = var.github_oidc_principal_id
}

resource "azurerm_role_assignment" "github_oidc_acr_push" {
  count = local.create_separate_github_oidc_assignments ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPush"
  principal_id         = var.github_oidc_principal_id
}

resource "azurerm_role_assignment" "github_oidc_acr_reader" {
  count = local.create_separate_github_oidc_assignments ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "Reader"
  principal_id         = var.github_oidc_principal_id
}

resource "azurerm_role_assignment" "github_oidc_acr_tasks_contributor" {
  count = local.create_separate_github_oidc_assignments ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "Container Registry Tasks Contributor"
  principal_id         = var.github_oidc_principal_id
}