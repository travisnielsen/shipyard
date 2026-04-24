# Network fabric for all workloads, including private DNS and egress controls.
module "networking" {
  source           = "Azure/avm-res-network-virtualnetwork/azurerm"
  version          = "0.17.1"
  enable_telemetry = false

  name          = "vnet-${var.prefix}"
  location      = var.location
  parent_id     = azurerm_resource_group.this.id
  address_space = [var.vnet_cidr]
  tags          = var.tags

  subnets = {
    infra = {
      name                            = "snet-${var.prefix}-infra"
      address_prefix                  = var.subnet_cidrs.infra
      service_endpoints_with_location = []
    }
    aks_nodes = {
      name                              = "snet-${var.prefix}-aks"
      address_prefix                    = var.subnet_cidrs.aks_nodes
      nat_gateway                       = local.effective_egress_mode == "nat_gateway" ? { id = azurerm_nat_gateway.workload[0].id } : null
      route_table                       = local.effective_egress_mode == "managed_firewall" ? { id = azurerm_route_table.managed_egress[0].id } : null
      network_security_group            = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-aks-nsg-${var.location}" }
      private_endpoint_network_policies = "Disabled"
      service_endpoints_with_location   = []
    }
    acr_tasks = {
      name                            = "snet-${var.prefix}-acr-tasks"
      address_prefix                  = var.subnet_cidrs.acr_tasks
      nat_gateway                     = local.effective_egress_mode == "nat_gateway" ? { id = azurerm_nat_gateway.workload[0].id } : null
      route_table                     = local.effective_egress_mode == "managed_firewall" ? { id = azurerm_route_table.managed_egress[0].id } : null
      service_endpoints_with_location = []
    }
    private_endpoints = {
      name                              = "snet-${var.prefix}-pep"
      address_prefix                    = var.subnet_cidrs.private_endpoints
      network_security_group            = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-pep-nsg-${var.location}" }
      private_endpoint_network_policies = "Disabled"
      service_endpoints_with_location   = []
    }
    vdi_integration = {
      name                            = "snet-${var.prefix}-vdi"
      address_prefix                  = var.subnet_cidrs.vdi_integration
      nat_gateway                     = local.effective_egress_mode == "nat_gateway" ? { id = azurerm_nat_gateway.workload[0].id } : null
      route_table                     = local.effective_egress_mode == "managed_firewall" ? { id = azurerm_route_table.managed_egress[0].id } : null
      network_security_group          = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-vdi-nsg-${var.location}" }
      service_endpoints_with_location = []
    }
    dev_vm = {
      name                            = "snet-${var.prefix}-vm"
      address_prefix                  = var.subnet_cidrs.dev_vm
      nat_gateway                     = local.effective_egress_mode == "nat_gateway" ? { id = azurerm_nat_gateway.workload[0].id } : null
      route_table                     = local.effective_egress_mode == "managed_firewall" ? { id = azurerm_route_table.managed_egress[0].id } : null
      network_security_group          = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-snet-${var.prefix}-vm-nsg-${var.location}" }
      service_endpoints_with_location = []
    }
    bastion = {
      name                            = "AzureBastionSubnet"
      address_prefix                  = var.subnet_cidrs.bastion
      network_security_group          = { id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Network/networkSecurityGroups/vnet-${var.prefix}-AzureBastionSubnet-nsg-${var.location}" }
      service_endpoints_with_location = []
    }
  }
}

# ============================================================================
# OUTBOUND EGRESS MODE SELECTION & ROUTING
# ============================================================================
# Managed egress mode (via Azure Firewall) is mutually exclusive with NAT Gateway.
# - If managed_egress_enabled=true: NAT Gateway resources are NOT created; 
#   instead, hub VNet and firewall provide egress via UDR-based steering.
# - If managed_egress_enabled=false: NAT Gateway provides standard outbound access.
# See locals.tf for effective_egress_mode determination.
#
# MODE TRANSITIONS:
# - NAT -> Managed: Set managed_egress_enabled=true and enable_nat_gateway=false in same apply.
#   Terraform will destroy NAT resources and create firewall/hub resources in one operation.
#   Outbound remains stable due to UDR steering (no downtime expected).
#
# - Managed -> NAT: Set managed_egress_enabled=false and enable_nat_gateway=true in same apply.
#   Terraform will destroy firewall/hub resources and create NAT Gateway in one operation.
#   Subnet associations are immediately updated; workloads may experience brief connectivity
#   gap if restarted during transition. Plan carefully for production environments.
#
# SAFEGUARDS:
# - Mutual exclusivity validation enforced in locals.tf; contradictory configurations will fail.
# - NAT Gateway and Azure Firewall resources use count conditions keyed to effective_egress_mode.
# - Subnet NAT associations are nullified during managed mode; firewall UDRs take over.
# - No manual cleanup required; Terraform handles resource lifecycle automatically.

# Explicit outbound egress for isolated VM subnet (NAT Mode Only)
resource "azurerm_public_ip" "workload_nat" {
  count = local.effective_egress_mode == "nat_gateway" ? 1 : 0

  name                = "pip-${var.prefix}-vm-nat"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    # Azure may surface provider-computed values with shape drift (null vs []),
    # which can otherwise force replacement of Public IPs and dependent resources.
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

resource "azurerm_nat_gateway" "workload" {
  count = local.effective_egress_mode == "nat_gateway" ? 1 : 0

  name                = "nat-${var.prefix}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "workload" {
  count = local.effective_egress_mode == "nat_gateway" ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.workload[0].id
  public_ip_address_id = azurerm_public_ip.workload_nat[0].id
}

module "private_dns_acr" {
  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.5.0"
  enable_telemetry = false

  domain_name = "privatelink.azurecr.io"
  parent_id   = azurerm_resource_group.this.id
  tags        = var.tags

  virtual_network_links = {
    vnet_link = {
      name               = "link-${var.prefix}-acr"
      virtual_network_id = module.networking.resource_id
    }
  }
}

# Separate zones keep service-specific private endpoint resolution explicit.
module "private_dns_keyvault" {
  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.5.0"
  enable_telemetry = false

  domain_name = "privatelink.vaultcore.azure.net"
  parent_id   = azurerm_resource_group.this.id
  tags        = var.tags

  virtual_network_links = {
    vnet_link = {
      name               = "link-${var.prefix}-kv"
      virtual_network_id = module.networking.resource_id
    }
  }
}

module "private_dns_storage" {
  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.5.0"
  enable_telemetry = false

  domain_name = "privatelink.file.core.windows.net"
  parent_id   = azurerm_resource_group.this.id
  tags        = var.tags

  virtual_network_links = {
    vnet_link = {
      name               = "link-${var.prefix}-storage"
      virtual_network_id = module.networking.resource_id
    }
  }
}

# ============================================================================
# MANAGED EGRESS HUB VNet (T016)
# ============================================================================
# Dedicated hub VNet for Azure Firewall in managed egress mode.
# Hub VNet CIDR must not overlap with spoke (10.70.0.0/16).
resource "azurerm_virtual_network" "managed_egress_hub" {
  count = var.managed_egress_enabled ? 1 : 0

  name                = "vnet-${var.prefix}-egress-hub"
  address_space       = [var.managed_egress_hub_vnet_cidr]
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

# Azure Firewall subnet (must be named AzureFirewallSubnet per Azure requirements)
resource "azurerm_subnet" "firewall_subnet" {
  count = var.managed_egress_enabled ? 1 : 0

  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.managed_egress_hub[0].name
  address_prefixes     = [var.managed_egress_hub_subnet_cidrs.azure_firewall]
}

# ============================================================================
# AZURE FIREWALL PUBLIC IP (T017)
# ============================================================================
resource "azurerm_public_ip" "firewall" {
  count = var.managed_egress_enabled ? 1 : 0

  name                = "pip-${var.prefix}-firewall"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

# ============================================================================
# AZURE FIREWALL RESOURCE (T017)
# ============================================================================
# Firewall is created but not associated with policy yet; policy configuration
# happens in Phase 5 (US3) when outbound control rules are defined.
resource "azurerm_firewall" "managed_egress" {
  count = var.managed_egress_enabled ? 1 : 0

  name                = "fw-${var.prefix}-egress"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.managed_egress_firewall_sku
  firewall_policy_id  = azurerm_firewall_policy.managed_egress[0].id
  tags                = var.tags

  ip_configuration {
    name                 = "firewall-ipconfig"
    subnet_id            = azurerm_subnet.firewall_subnet[0].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  depends_on = [
    azurerm_subnet.firewall_subnet
  ]
}

# ============================================================================
# VNet PEERING - Spoke to Hub (T018)
# ============================================================================
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = var.managed_egress_enabled ? 1 : 0

  name                         = "peer-${var.prefix}-spoke-to-hub"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = module.networking.name
  remote_virtual_network_id    = azurerm_virtual_network.managed_egress_hub[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ============================================================================
# VNet PEERING - Hub to Spoke (T018)
# ============================================================================
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count = var.managed_egress_enabled ? 1 : 0

  name                         = "peer-${var.prefix}-hub-to-spoke"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.managed_egress_hub[0].name
  remote_virtual_network_id    = module.networking.resource_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ============================================================================
# MANAGED EGRESS ROUTE TABLES & UDRs (T019)
# ============================================================================
# Route table with default route to firewall for outbound-capable subnets.
# UDR next hop is the firewall's private IP address.
resource "azurerm_route_table" "managed_egress" {
  count = var.managed_egress_enabled ? 1 : 0

  name                = "rt-${var.prefix}-egress-managed"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  route {
    name                   = "route-firewall-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.managed_egress[0].ip_configuration[0].private_ip_address
  }

  depends_on = [
    azurerm_firewall.managed_egress
  ]
}

# ============================================================================
# ROUTE TABLE ASSOCIATIONS (T020)
# ============================================================================
# Managed egress route-table binding is defined in module.networking subnet
# definitions via each subnet's route_table attribute, and explicitly enforced
# here so Terraform can track association drift directly.

resource "azurerm_subnet_route_table_association" "managed_egress" {
  for_each = var.managed_egress_enabled ? {
    aks_nodes       = module.networking.subnets["aks_nodes"].resource_id
    acr_tasks       = module.networking.subnets["acr_tasks"].resource_id
    vdi_integration = module.networking.subnets["vdi_integration"].resource_id
    dev_vm          = module.networking.subnets["dev_vm"].resource_id
  } : {}

  subnet_id      = each.value
  route_table_id = azurerm_route_table.managed_egress[0].id
}

# ============================================================================
# FIREWALL POLICY - CONFIGURABLE FALLBACK ACTION (T027)
# ============================================================================
# Firewall policy fallback action is configurable for rollout safety:
# - Allow: initial allow-by-default baseline
# - Deny: strict allow-list posture
resource "azurerm_firewall_policy" "managed_egress" {
  count = var.managed_egress_enabled ? 1 : 0

  name                     = local.managed_egress_firewall_policy_name
  location                 = var.location
  resource_group_name      = azurerm_resource_group.this.name
  threat_intelligence_mode = "Alert"
  dns {
    servers       = []
    proxy_enabled = var.managed_egress_enable_dns_proxy
  }
  tags = var.tags
}

# ============================================================================
# APPLICATION RULE COLLECTION - FQDN Allow-List (T028)
# ============================================================================
# Application rules enforce DNS/FQDN-based outbound filtering.
# Platform-critical FQDNs are auto-merged with user-defined allow-list.
resource "azurerm_firewall_policy_rule_collection_group" "managed_egress_app_rules" {
  count = var.managed_egress_enabled ? 1 : 0

  name               = "rcg-app-rules"
  firewall_policy_id = azurerm_firewall_policy.managed_egress[0].id
  priority           = 100

  application_rule_collection {
    name     = "arc-allow-fqdns"
    priority = 100
    action   = "Allow"

    dynamic "rule" {
      for_each = length(local.managed_egress_fqdns_effective) > 0 ? [1] : []
      content {
        name              = "rule-allow-list"
        source_addresses  = ["*"]
        destination_fqdns = local.managed_egress_fqdns_effective
        protocols {
          type = "Http"
          port = 80
        }
        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }

  depends_on = [
    azurerm_firewall_policy.managed_egress
  ]
}

# ============================================================================
# NETWORK RULE COLLECTION - IP Destination Allow-List (T029)
# ============================================================================
# Network rules handle non-FQDN IP/CIDR destinations (optional).
resource "azurerm_firewall_policy_rule_collection_group" "managed_egress_net_rules" {
  count = var.managed_egress_enabled && length(var.managed_egress_allow_ip_destinations) > 0 ? 1 : 0

  name               = "rcg-net-rules"
  firewall_policy_id = azurerm_firewall_policy.managed_egress[0].id
  priority           = 200

  network_rule_collection {
    name     = "nrc-allow-ip-destinations"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "rule-allow-ip-list"
      source_addresses      = ["*"]
      destination_addresses = var.managed_egress_allow_ip_destinations
      protocols             = ["TCP", "UDP"]
      destination_ports     = ["*"]
    }
  }

  depends_on = [
    azurerm_firewall_policy.managed_egress
  ]
}

# ============================================================================
# DEFAULT FALLBACK COLLECTIONS (T030)
# ============================================================================
# Azure Firewall is deny-by-default. The fallback collections below make
# initial deployments allow-by-default when configured to "Allow".
resource "azurerm_firewall_policy_rule_collection_group" "managed_egress_default_fallback" {
  count = var.managed_egress_enabled ? 1 : 0

  name               = "rcg-default-fallback"
  firewall_policy_id = azurerm_firewall_policy.managed_egress[0].id
  priority           = 65000 # Highest priority = last to evaluate

  application_rule_collection {
    name     = "arc-default-fallback-app"
    priority = 65000
    action   = var.managed_egress_default_rule_action

    rule {
      name              = "rule-default-fallback-all"
      source_addresses  = ["*"]
      destination_fqdns = ["*"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  network_rule_collection {
    name     = "nrc-default-fallback-network"
    priority = 64999
    action   = var.managed_egress_default_rule_action

    rule {
      name                  = "rule-default-fallback-all"
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      protocols             = ["TCP", "UDP", "ICMP"]
      destination_ports     = ["*"]
    }
  }

  depends_on = [
    azurerm_firewall_policy.managed_egress
  ]
}