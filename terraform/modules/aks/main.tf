resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${replace(var.prefix, "-", "")}"
  kubernetes_version  = null
  private_cluster_enabled = true
  azure_policy_enabled    = true
  role_based_access_control_enabled = true
  local_account_disabled  = true
  tags                    = var.tags

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size
    type                = "VirtualMachineScaleSets"
    vnet_subnet_id      = var.subnet_id
    enable_auto_scaling = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    outbound_type  = "loadBalancer"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
