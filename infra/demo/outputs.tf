output "resource_group_name" {
  value       = azurerm_resource_group.this.name
  description = "Resource group name for demo deployment."
}

output "vnet_id" {
  value       = module.networking.resource_id
  description = "VNet ID for the demo environment."
}

output "acr_login_server" {
  value       = module.container_registry.resource.login_server
  description = "Private ACR login server."
}

output "aks_cluster_name" {
  value       = module.aks[0].name
  description = "AKS cluster name."
}

output "storage_account_name" {
  value       = azurerm_storage_account.this.name
  description = "Storage account name for dev workspace file shares. Pass to provision-workspace.sh."
}

output "storage_account_resource_group" {
  value       = azurerm_resource_group.this.name
  description = "Resource group of the workspace storage account. Pass to provision-workspace.sh."
}

output "dev_vm_name" {
  value       = var.deploy_test_vm ? azurerm_windows_virtual_machine.dev_vm[0].name : null
  description = "Name of the isolated workload VM used for remote dev container testing."
}

output "dev_vm_private_ip" {
  value       = var.deploy_test_vm ? azurerm_network_interface.dev_vm[0].private_ip_address : null
  description = "Private IP address of the isolated workload VM."
}

output "dev_vm_subnet_id" {
  value       = var.deploy_test_vm ? module.networking.subnets["dev_vm"].resource_id : null
  description = "Subnet ID for the isolated workload VM network segment."
}

output "workload_nat_gateway_id" {
  value       = var.enable_nat_gateway ? azurerm_nat_gateway.workload[0].id : null
  description = "NAT Gateway ID used for outbound internet access from workload subnets."
}

output "workload_nat_associated_subnet_id" {
  value       = var.enable_nat_gateway ? try(module.networking.subnets["dev_vm"].resource_id, null) : null
  description = "Representative subnet ID associated with the workload NAT Gateway."
}

output "dev_vm_nat_gateway_id" {
  value       = var.enable_nat_gateway ? azurerm_nat_gateway.workload[0].id : null
  description = "Deprecated alias for workload_nat_gateway_id."
}

output "dev_vm_nat_associated_subnet_id" {
  value       = var.enable_nat_gateway ? try(module.networking.subnets["dev_vm"].resource_id, null) : null
  description = "Deprecated alias for workload_nat_associated_subnet_id."
}

output "bastion_name" {
  value       = var.deploy_test_vm ? azurerm_bastion_host.workload[0].name : null
  description = "Name of the Azure Bastion host for private RDP access to the workload VM."
}

output "bastion_public_ip" {
  value       = var.deploy_test_vm ? azurerm_public_ip.bastion[0].ip_address : null
  description = "Public IP of the Azure Bastion host."
}
