resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  compact_prefix = substr(replace(var.prefix, "-", ""), 0, 10)
  acr_name       = "${local.compact_prefix}${random_string.suffix.result}acr"
  kv_name        = substr("${local.compact_prefix}${random_string.suffix.result}kv", 0, 24)
}

resource "azurerm_container_registry" "this" {
  name                          = local.acr_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pep-${var.prefix}-acr"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.prefix}-acr"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-acr"
    private_dns_zone_ids = [var.acr_private_dns_zone_id]
  }
}

resource "azurerm_key_vault" "this" {
  name                          = local.kv_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  enabled_for_disk_encryption   = false
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "pep-${var.prefix}-kv"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.prefix}-kv"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-kv"
    private_dns_zone_ids = [var.kv_private_dns_zone_id]
  }
}
