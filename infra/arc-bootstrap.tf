resource "terraform_data" "arc_bootstrap" {
  count = local.deploy_aks && var.arc_bootstrap_enabled ? 1 : 0

  # Trigger re-execution only when bootstrap inputs or scripts change.
  triggers_replace = [
    module.aks[0].resource_id,
    local.arc_bootstrap_script_hash,
    jsonencode(local.arc_bootstrap_trigger_inputs),
  ]

  provisioner "local-exec" {
    # Bootstrap remains opt-in and script-driven to keep ARC rollout explicit.
    command = local.arc_bootstrap_command
    environment = merge(
      local.arc_bootstrap_environment,
      {
        AKS_CLUSTER_NAME      = module.aks[0].name
        AKS_RESOURCE_GROUP    = azurerm_resource_group.this.name
        AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
      }
    )
  }

  depends_on = [module.aks]
}