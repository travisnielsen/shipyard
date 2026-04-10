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
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  name          = "vnet-${var.prefix}"
  location      = var.location
  parent_id     = azurerm_resource_group.this.id
  address_space = [var.vnet_cidr]
  tags          = var.tags

  subnets = {
    infra = {
      name             = "snet-${var.prefix}-infra"
      address_prefixes = [var.subnet_cidrs.infra]
    }
    aks_nodes = {
      name             = "snet-${var.prefix}-aks"
      address_prefixes = [var.subnet_cidrs.aks_nodes]
      nat_gateway      = var.enable_nat_gateway ? { id = azurerm_nat_gateway.workload[0].id } : null
    }
    private_endpoints = {
      name                              = "snet-${var.prefix}-pep"
      address_prefixes                  = [var.subnet_cidrs.private_endpoints]
      private_endpoint_network_policies = "Disabled"
    }
    vdi_integration = {
      name             = "snet-${var.prefix}-vdi"
      address_prefixes = [var.subnet_cidrs.vdi_integration]
    }
    dev_vm = {
      name             = "snet-${var.prefix}-vm"
      address_prefixes = [var.subnet_cidrs.dev_vm]
      nat_gateway      = var.enable_nat_gateway ? { id = azurerm_nat_gateway.workload[0].id } : null
    }
    bastion = {
      name             = "AzureBastionSubnet"
      address_prefixes = [var.subnet_cidrs.bastion]
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
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
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
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

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
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

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
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

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
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

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

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

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
  name                          = lower(substr("${replace(var.prefix, "-", "")}${local.identifier}sa", 0, 24))
  resource_group_name           = azurerm_resource_group.this.name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false
  shared_access_key_enabled     = false

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
  count   = local.deploy_aks ? 1 : 0
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.5.3"

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

  agent_pools = var.aks_user_pool_enabled ? {
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
  } : {}

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

# Required for dynamic Azure Files share lifecycle operations (create/read/delete)
# performed by the CSI provisioner against the storage account ARM resource.
resource "azurerm_role_assignment" "aks_storage_account_contributor" {
  count = local.deploy_aks ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Account Contributor"
  principal_id = coalesce(
    try(module.aks[0].kubelet_identity.object_id, null),
    try(module.aks[0].kubelet_identity.objectId, null)
  )
}

# Required for SMB OAuth data-path access to the provisioned file share.
resource "azurerm_role_assignment" "aks_storage_file_share_contributor" {
  count = local.deploy_aks ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id = coalesce(
    try(module.aks[0].kubelet_identity.object_id, null),
    try(module.aks[0].kubelet_identity.objectId, null)
  )
}

# ---------------------------------------------------------------------------
# Identity / RBAC baselines
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "platform_admins_kv_admin" {
  count = var.platform_admins_group_id != null ? 1 : 0

  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.platform_admins_group_id
}

resource "azurerm_role_assignment" "platform_admins_acr_push" {
  count = var.platform_admins_group_id != null ? 1 : 0

  scope                = module.container_registry.resource_id
  role_definition_name = "AcrPush"
  principal_id         = var.platform_admins_group_id
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

resource "azurerm_role_assignment" "workspace_cluster_admin_aks_cluster_admin" {
  count = local.deploy_aks && var.workspace_cluster_admin_group_id != null ? 1 : 0

  scope                = module.aks[0].resource_id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = var.workspace_cluster_admin_group_id
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


