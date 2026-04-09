resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.prefix}-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${var.prefix}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id       = var.subnet_id
  internal_load_balancer_enabled = true
  tags                           = var.tags
}

resource "azurerm_container_app" "dev_workspace" {
  name                         = "ca-${var.prefix}-workspace"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "dev-workspace"
      image  = var.image
      cpu    = 1.0
      memory = "2Gi"
    }

    min_replicas = 1
    max_replicas = 2
  }

  ingress {
    external_enabled = false
    target_port      = 8443

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
