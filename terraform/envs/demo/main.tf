resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "networking" {
  source = "../../modules/networking"

  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = var.vnet_cidr
  subnet_cidrs        = var.subnet_cidrs
  tags                = var.tags
}

module "platform_services" {
  source = "../../modules/platform_services"

  prefix                   = var.prefix
  location                 = var.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  resource_group_name      = azurerm_resource_group.this.name
  private_endpoints_subnet = module.networking.private_endpoints_subnet_id
  acr_private_dns_zone_id  = module.networking.acr_private_dns_zone_id
  kv_private_dns_zone_id   = module.networking.kv_private_dns_zone_id
  tags                     = var.tags

  depends_on = [module.networking]
}

module "aks" {
  count  = local.deploy_aks ? 1 : 0
  source = "../../modules/aks"

  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.networking.aks_nodes_subnet_id
  node_count          = var.aks_node_count
  vm_size             = var.aks_vm_size
  acr_id              = module.platform_services.acr_id
  tags                = var.tags

  depends_on = [module.platform_services]
}

module "container_apps" {
  count  = local.deploy_container_apps ? 1 : 0
  source = "../../modules/container_apps"

  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.networking.container_apps_subnet_id
  image               = var.container_app_image
  tags                = var.tags

  depends_on = [module.platform_services]
}
