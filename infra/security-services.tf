# Security services: centralized Key Vault with private endpoint access only.
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