# Foundation resources kept in main.tf by convention.
# Domain-specific resources live in dedicated *.tf files.
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Random identifier for globally unique DNS names (storage account, ACR)
resource "random_string" "naming" {
  special = false
  upper   = false
  length  = 5
}

resource "random_string" "alpha_prefix" {
  special = false
  upper   = false
  length  = 1
  lower   = true
  numeric = false
}

moved {
  from = azurerm_public_ip.dev_vm_nat
  to   = azurerm_public_ip.workload_nat
}

moved {
  from = azurerm_nat_gateway.dev_vm
  to   = azurerm_nat_gateway.workload
}

moved {
  from = azurerm_nat_gateway_public_ip_association.dev_vm
  to   = azurerm_nat_gateway_public_ip_association.workload
}


