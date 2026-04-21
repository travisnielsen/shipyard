# AKS cluster and AKS-managed identity permissions required by this topology.
module "aks" {
  count            = local.deploy_aks ? 1 : 0
  source           = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version          = "0.5.3"
  enable_telemetry = false

  name      = "aks-${var.prefix}-${local.identifier}"
  location  = var.location
  parent_id = azurerm_resource_group.this.id

  enable_rbac            = true
  disable_local_accounts = true

  # Azure AD integration required when disable_local_accounts = true (Kubernetes 1.25+)
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
  }

  addon_profile_azure_policy = {
    enabled = true
  }

  default_agent_pool = {
    name           = "system"
    vm_size        = var.aks_vm_size
    count_of       = var.aks_node_count
    mode           = "System"
    vnet_subnet_id = module.networking.subnets["aks_nodes"].resource_id
    type           = "VirtualMachineScaleSets"
  }

  agent_pools = merge(
    var.aks_user_pool_enabled ? {
      user = {
        name                = "user"
        vm_size             = var.aks_user_pool_vm_size
        mode                = "User"
        type                = "VirtualMachineScaleSets"
        enable_auto_scaling = true
        min_count           = var.aks_user_pool_min_count
        max_count           = var.aks_user_pool_max_count
        vnet_subnet_id      = module.networking.subnets["aks_nodes"].resource_id
        node_labels = {
          workload = "devworkspace"
        }
        node_taints = [
          "workload=devworkspace:NoSchedule"
        ]
      }
    } : {},
    var.arc_runner_nodepool_enabled ? {
      runner = {
        name                = local.arc_runner_nodepool_name
        vm_size             = var.arc_runner_nodepool_vm_size
        mode                = "User"
        type                = "VirtualMachineScaleSets"
        enable_auto_scaling = true
        min_count           = local.arc_runner_nodepool_effective_min_count
        max_count           = var.arc_runner_nodepool_max_count
        vnet_subnet_id      = module.networking.subnets["aks_nodes"].resource_id
        node_labels         = local.arc_runner_node_labels
        node_taints         = local.arc_runner_node_taints
      }
    } : {},
  )

  network_profile = {
    network_plugin = "azure"
    network_policy = "azure"
    outbound_type  = "loadBalancer"
  }

  api_server_access_profile = {
    enable_private_cluster = true
    private_dns_zone       = "system"
  }

  oidc_issuer_profile = {
    enabled = true
  }

  security_profile = {
    workload_identity = {
      enabled = true
    }
  }

  storage_profile = {
    # Keep AVM storage_profile keys aligned with module expectations.
    blob_csi_driver = {
      enabled = false
    }
    disk_csi_driver = {
      enabled = true
    }
    file_csi_driver = {
      enabled = true
    }
    snapshot_controller = {
      enabled = true
    }
  }

  tags = var.tags
}