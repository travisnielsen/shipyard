# Network fabric for all workloads, including private DNS and egress controls.
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

# Separate zones keep service-specific private endpoint resolution explicit.
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