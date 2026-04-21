# DevOps service plane: private ACR and optional private ACR task agent pool.
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