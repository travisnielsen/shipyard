output "resource_group_name" {
  value       = azurerm_resource_group.this.name
  description = "Resource group name for demo deployment."
}

output "vnet_id" {
  value       = module.networking.vnet_id
  description = "VNet ID for the demo environment."
}

output "acr_login_server" {
  value       = module.platform_services.acr_login_server
  description = "Private ACR login server."
}

output "aks_cluster_name" {
  value       = local.deploy_aks ? module.aks[0].name : null
  description = "AKS cluster name when AKS is deployed."
}

output "container_app_fqdn" {
  value       = local.deploy_container_apps ? module.container_apps[0].fqdn : null
  description = "Internal FQDN for demo container app when ACA is deployed."
}
