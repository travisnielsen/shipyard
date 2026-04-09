output "environment_id" {
  value = azurerm_container_app_environment.this.id
}

output "app_name" {
  value = azurerm_container_app.dev_workspace.name
}

output "fqdn" {
  value = azurerm_container_app.dev_workspace.latest_revision_fqdn
}
