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
  # File subresource endpoint keeps SMB traffic private for workspace shares.
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