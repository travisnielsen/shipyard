output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "aks_nodes_subnet_id" {
  value = azurerm_subnet.aks_nodes.id
}

output "container_apps_subnet_id" {
  value = azurerm_subnet.container_apps_env.id
}

output "private_endpoints_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "acr_private_dns_zone_id" {
  value = azurerm_private_dns_zone.acr.id
}

output "kv_private_dns_zone_id" {
  value = azurerm_private_dns_zone.keyvault.id
}
