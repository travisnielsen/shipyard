resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Random identifier for globally unique DNS names (storage account, ACR)
resource "random_string" "naming" {
  special = false
  upper   = false
  length  = 5
}

resource "random_string" "alpha_prefix" {
  special = false
  upper   = false
  length  = 1
  lower   = true
  numeric = false
}

moved {
  from = azurerm_public_ip.dev_vm_nat
  to   = azurerm_public_ip.workload_nat
}

moved {
  from = azurerm_nat_gateway.dev_vm
  to   = azurerm_nat_gateway.workload
}

moved {
  from = azurerm_nat_gateway_public_ip_association.dev_vm
  to   = azurerm_nat_gateway_public_ip_association.workload
}

module "networking" {
  source           = "Azure/avm-res-network-virtualnetwork/azurerm"
  version          = "0.17.1"
  enable_telemetry = false

  name          = "vnet-${var.prefix}"
  location      = var.location
  parent_id     = azurerm_resource_group.this.id
  address_space = [var.vnet_cidr]
  tags          = var.tags

  subnets = {
    infra = {
      name                            = "snet-${var.prefix}-infra"
      address_prefix                  = var.subnet_cidrs.infra
      service_endpoints_with_location = []
    }
    aks_nodes = {
      name                              = "snet-${var.prefix}-aks"
      address_prefix                    = var.subnet_cidrs.aks_nodes
      nat_gateway                       = var.enable_nat_gateway ? { id = azurerm_nat_gateway.workload[0].id } : null
      network_security_group            = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-aks-nsg-${var.location}" }
      private_endpoint_network_policies = "Disabled"
      service_endpoints_with_location   = []
    }
    acr_tasks = {
      name                            = "snet-${var.prefix}-acr-tasks"
      address_prefix                  = var.subnet_cidrs.acr_tasks
      nat_gateway                     = var.enable_nat_gateway ? { id = azurerm_nat_gateway.workload[0].id } : null
      service_endpoints_with_location = []
    }
    private_endpoints = {
      name                              = "snet-${var.prefix}-pep"
      address_prefix                    = var.subnet_cidrs.private_endpoints
      network_security_group            = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-pep-nsg-${var.location}" }
      private_endpoint_network_policies = "Disabled"
      service_endpoints_with_location   = []
    }
    vdi_integration = {
      name                            = "snet-${var.prefix}-vdi"
      address_prefix                  = var.subnet_cidrs.vdi_integration
      nat_gateway                     = var.enable_nat_gateway ? { id = azurerm_nat_gateway.workload[0].id } : null
      network_security_group          = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-vdi-nsg-${var.location}" }
      service_endpoints_with_location = []
    }
    dev_vm = {
      name                            = "snet-${var.prefix}-vm"
      address_prefix                  = var.subnet_cidrs.dev_vm
      nat_gateway                     = var.enable_nat_gateway ? { id = azurerm_nat_gateway.workload[0].id } : null
      network_security_group          = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-vm-nsg-${var.location}" }
      service_endpoints_with_location = []
    }
    bastion = {
      name                            = "AzureBastionSubnet"
      address_prefix                  = var.subnet_cidrs.bastion
      network_security_group          = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-AzureBastionSubnet-nsg-${var.location}" }
      service_endpoints_with_location = []
    }
  }
}

# Explicit outbound egress for isolated VM subnet.
resource "azurerm_public_ip" "workload_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  name                = "pip-${var.prefix}-vm-nat"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    # Azure may surface provider-computed values with shape drift (null vs []),
    # which can otherwise force replacement of Public IPs and dependent resources.
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

resource "azurerm_nat_gateway" "workload" {
  count = var.enable_nat_gateway ? 1 : 0

  name                = "nat-${var.prefix}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "workload" {
  count = var.enable_nat_gateway ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.workload[0].id
  public_ip_address_id = azurerm_public_ip.workload_nat[0].id
}

resource "azurerm_network_interface" "dev_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "nic-${var.prefix}-workload-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.networking.subnets["dev_vm"].resource_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "dev_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "vm-${var.prefix}"
  computer_name       = "vm-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.dev_vm_size
  admin_username      = "azureuser"
  admin_password      = var.dev_vm_admin_password
  network_interface_ids = [
    azurerm_network_interface.dev_vm[0].id
  ]

  os_disk {
    caching = "ReadWrite"
    # Keep test VM non-disruptive during drift reconciliation; Premium would force replacement.
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-25h2-pro"
    version   = "latest"
  }

  lifecycle {
    # Azure Policy may attach a system-assigned identity after creation.
    ignore_changes = [identity]
  }

  tags = var.tags
}

resource "azurerm_public_ip" "bastion" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "pip-${var.prefix}-bastion"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    # Prevent forced replacement churn from Azure/provider normalization-only drift.
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

resource "azurerm_bastion_host" "workload" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "bas-${var.prefix}-workload"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"
  copy_paste_enabled  = true
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = module.networking.subnets["bastion"].resource_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }


  timeouts {
    create = "45m"
    update = "45m"
  }
}

module "private_dns_acr" {
  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.5.0"
  enable_telemetry = false

  domain_name = "privatelink.azurecr.io"
  parent_id   = azurerm_resource_group.this.id
  tags        = var.tags

  virtual_network_links = {
    vnet_link = {
      name               = "link-${var.prefix}-acr"
      virtual_network_id = module.networking.resource_id
    }
  }
}

module "private_dns_keyvault" {
  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.5.0"
  enable_telemetry = false

  domain_name = "privatelink.vaultcore.azure.net"
  parent_id   = azurerm_resource_group.this.id
  tags        = var.tags

  virtual_network_links = {
    vnet_link = {
      name               = "link-${var.prefix}-kv"
      virtual_network_id = module.networking.resource_id
    }
  }
}

module "private_dns_storage" {
  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.5.0"
  enable_telemetry = false

  domain_name = "privatelink.file.core.windows.net"
  parent_id   = azurerm_resource_group.this.id
  tags        = var.tags

  virtual_network_links = {
    vnet_link = {
      name               = "link-${var.prefix}-storage"
      virtual_network_id = module.networking.resource_id
    }
  }
}

module "container_registry" {
  source           = "Azure/avm-res-containerregistry-registry/azurerm"
  version          = "0.5.1"
  enable_telemetry = false

  name                = lower(substr("${replace(var.prefix, "-", "")}${local.identifier}acr", 0, 50))
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Premium"
  admin_enabled       = false

  public_network_access_enabled = false
  # Required so ACR Tasks (az acr build) can authenticate in a locked-down registry.
  network_rule_bypass_option = "AzureServices"
  network_rule_set = {
    default_action = "Deny"
  }

  private_endpoints = {
    registry = {
      subnet_resource_id            = module.networking.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [module.private_dns_acr.resource_id]
    }
  }

  tags = var.tags

  depends_on = [module.private_dns_acr]
}

resource "azurerm_container_registry_agent_pool" "private_tasks" {
  count = var.enable_private_acr_tasks ? 1 : 0

  name                      = var.acr_task_agentpool_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = var.location
  container_registry_name   = module.container_registry.resource.name
  instance_count            = var.acr_task_agentpool_instance_count
  tier                      = var.acr_task_agentpool_tier
  virtual_network_subnet_id = module.networking.subnets["acr_tasks"].resource_id
  tags                      = var.tags

  depends_on = [module.container_registry]
}

module "key_vault" {
  source           = "Azure/avm-res-keyvault-vault/azurerm"
  version          = "0.10.2"
  enable_telemetry = false

  name                = lower(substr("${replace(var.prefix, "-", "")}-${local.identifier}kv", 0, 24))
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  public_network_access_enabled = false
  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      subnet_resource_id            = module.networking.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [module.private_dns_keyvault.resource_id]
    }
  }

  tags = var.tags

  depends_on = [module.private_dns_keyvault]
}

# ---------------------------------------------------------------------------
# Shared storage (Azure Files for dev workspace PVs)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                            = lower(substr("${replace(var.prefix, "-", "")}${local.identifier}sa", 0, 24))
  resource_group_name             = azurerm_resource_group.this.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  shared_access_key_enabled       = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "storage_file" {
  name                = "pep-${var.prefix}-storage-file"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.networking.subnets["private_endpoints"].resource_id

  private_service_connection {
    name                           = "psc-${var.prefix}-storage-file"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-${var.prefix}-storage-file"
    private_dns_zone_ids = [module.private_dns_storage.resource_id]
  }

  tags = var.tags

  depends_on = [module.private_dns_storage]
}

module "aks" {
  count            = local.deploy_aks ? 1 : 0
  source           = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version          = "0.5.3"
  enable_telemetry = false

  name      = "aks-${var.prefix}-${local.identifier}"
  location  = var.location
  parent_id = azurerm_resource_group.this.id

  enable_rbac            = true
  disable_local_accounts = true

  # Azure AD integration required when disable_local_accounts = true (Kubernetes 1.25+)
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
  }

  addon_profile_azure_policy = {
    enabled = true
  }

  default_agent_pool = {
    name           = "system"
    vm_size        = var.aks_vm_size
    count_of       = var.aks_node_count
    mode           = "System"
    vnet_subnet_id = module.networking.subnets["aks_nodes"].resource_id
    type           = "VirtualMachineScaleSets"
  }

  agent_pools = merge(
    var.aks_user_pool_enabled ? {
      user = {
        name                = "user"
        vm_size             = var.aks_user_pool_vm_size
        mode                = "User"
        type                = "VirtualMachineScaleSets"
        enable_auto_scaling = true
        min_count           = var.aks_user_pool_min_count
        max_count           = var.aks_user_pool_max_count
        vnet_subnet_id      = module.networking.subnets["aks_nodes"].resource_id
        node_labels = {
          workload = "devworkspace"
        }
        node_taints = [
          "workload=devworkspace:NoSchedule"
        ]
      }
    } : {},
    var.arc_runner_nodepool_enabled ? {
      runner = {
        name                = local.arc_runner_nodepool_name
        vm_size             = var.arc_runner_nodepool_vm_size
        mode                = "User"
        type                = "VirtualMachineScaleSets"
        enable_auto_scaling = true
        min_count           = local.arc_runner_nodepool_effective_min_count
        max_count           = var.arc_runner_nodepool_max_count
        vnet_subnet_id      = module.networking.subnets["aks_nodes"].resource_id
        node_labels         = local.arc_runner_node_labels
        node_taints         = local.arc_runner_node_taints
      }
    } : {},
  )

  network_profile = {
    network_plugin = "azure"
    network_policy = "azure"
    outbound_type  = "loadBalancer"
  }

  api_server_access_profile = {
    enable_private_cluster = true
    private_dns_zone       = "system"
  }

  oidc_issuer_profile = {
    enabled = true
  }

  security_profile = {
    workload_identity = {
      enabled = true
    }
  }

  storage_profile = {
    blob_csi_driver = {
      enabled = false
    }
    disk_csi_driver = {
      enabled = true
    }
    file_csi_driver = {
      enabled = true
    }
    snapshot_controller = {
      enabled = true
    }
  }

  tags = var.tags
}

resource "terraform_data" "arc_bootstrap" {
  count = local.deploy_aks && var.arc_bootstrap_enabled ? 1 : 0

  # Trigger re-execution only when bootstrap inputs or scripts change.
  triggers_replace = [
    module.aks[0].resource_id,
    local.arc_bootstrap_script_hash,
    jsonencode(local.arc_bootstrap_trigger_inputs),
  ]

  provisioner "local-exec" {
    command = local.arc_bootstrap_command
    environment = merge(
      local.arc_bootstrap_environment,
      {
        AKS_CLUSTER_NAME      = module.aks[0].name
        AKS_RESOURCE_GROUP    = azurerm_resource_group.this.name
        AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
      }
    )
  }

  depends_on = [module.aks]
}

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

# ---------------------------------------------------------------------------
# Identity / RBAC baselines
# ---------------------------------------------------------------------------

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

resource "azurerm_role_assignment" "current_principal_acr_push" {
  count = var.grant_current_principal_acr_push ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "workspace_user_aks_user" {
  count = local.deploy_aks && var.workspace_user_group_id != null ? 1 : 0

  scope                = module.aks[0].resource_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.workspace_user_group_id
}

resource "azurerm_role_assignment" "workspace_operators_aks_cluster_admin" {
  count = local.deploy_aks && var.workspace_operator_group_id != null ? 1 : 0

  scope                = module.aks[0].resource_id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = var.workspace_operator_group_id
}

resource "azurerm_role_assignment" "workspace_user_acr_pull" {
  count = var.workspace_user_group_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPull"
  principal_id         = var.workspace_user_group_id
}

resource "azurerm_role_assignment" "workspace_user_storage_file_contributor" {
  count = var.workspace_user_group_id != null ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.workspace_user_group_id
}

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

# GitHub Actions OIDC federated identity ACR permissions
locals {
  github_oidc_principal_id = var.github_oidc_principal_id != null ? var.github_oidc_principal_id : var.arc_runtime_principal_id
  # Only create separate assignments if the principals are different
  # Otherwise, the arc_runtime assignments above already cover the permissions
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


