resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-${var.prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-${var.prefix}-aca"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "infra" {
  name                 = "snet-${var.prefix}-infra"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.infra]
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-${var.prefix}-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.aks_nodes]
}

resource "azurerm_subnet" "container_apps_env" {
  name                 = "snet-${var.prefix}-aca"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.container_apps_env]

  delegation {
    name = "aca-delegation"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                                      = "snet-${var.prefix}-pep"
  resource_group_name                       = var.resource_group_name
  virtual_network_name                      = azurerm_virtual_network.this.name
  address_prefixes                          = [var.subnet_cidrs.private_endpoints]
  private_endpoint_network_policies         = "Disabled"
}

resource "azurerm_subnet" "vdi_integration" {
  name                 = "snet-${var.prefix}-vdi"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.vdi_integration]
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = azurerm_subnet.container_apps_env.id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-${var.prefix}-acr"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "link-${var.prefix}-kv"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.this.id
}
