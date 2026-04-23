locals {
  # Create unique identifier for DNS-sensitive resources (storage, ACR)
  # Format: <single-letter><5-random-lowercase-alphanumeric>
  # Example: a1b2c3
  identifier = "${random_string.alpha_prefix.result}${random_string.naming.result}"

  deploy_aks = true

  # Utility VM setup script aligned with Cadence bootstrap.
  utility_vm_setup_script = file("${path.module}/scripts/util_vm_setup_choco.ps1")

  arc_runner_nodepool_name = substr(var.arc_runner_nodepool_name, 0, 12)

  arc_runner_node_labels = merge(
    {
      workload = "github-runner"
      role     = "arc"
    },
    var.arc_runner_nodepool_labels,
  )

  arc_runner_node_taints = var.arc_runner_nodepool_taints

  arc_runner_nodepool_effective_min_count = (
    var.arc_runner_nodepool_min_count == 0 && !var.arc_runner_nodepool_scale_to_zero_supported
  ) ? 1 : var.arc_runner_nodepool_min_count

  arc_bootstrap_script_path = var.arc_bootstrap_script_shell == "powershell" ? var.arc_bootstrap_script_path_powershell : var.arc_bootstrap_script_path_bash
  arc_bootstrap_script_hash = filesha256("${path.module}/${local.arc_bootstrap_script_path}")

  arc_bootstrap_environment = {
    ARC_BOOTSTRAP_EXECUTION_MODE   = var.arc_bootstrap_execution_mode
    ARC_RUNNER_SCOPE               = var.arc_bootstrap_runner_scope
    ARC_RUNNER_CONFIG_URL          = coalesce(var.arc_bootstrap_config_url, "")
    ARC_GITHUB_APP_ID              = coalesce(var.arc_github_app_id, "")
    ARC_GITHUB_APP_INSTALLATION_ID = coalesce(var.arc_github_app_installation_id, "")
    ARC_GITHUB_APP_PRIVATE_KEY     = var.arc_github_app_private_key_path != null ? replace(file(var.arc_github_app_private_key_path), "\r\n", "\n") : ""
    ARC_RUNNER_LABELS              = join(",", var.arc_bootstrap_runner_labels)
    ARC_RUNNER_MIN_REPLICAS        = tostring(var.arc_runner_min_replicas)
    ARC_RUNNER_MAX_REPLICAS        = tostring(var.arc_runner_max_replicas)
    ARC_RUNNER_NODEPOOL_NAME       = local.arc_runner_nodepool_name
    ARC_RUNNER_IMAGE               = var.arc_runner_image
  }

  arc_bootstrap_trigger_inputs = {
    ARC_BOOTSTRAP_EXECUTION_MODE   = var.arc_bootstrap_execution_mode
    ARC_RUNNER_SCOPE               = var.arc_bootstrap_runner_scope
    ARC_RUNNER_CONFIG_URL          = coalesce(var.arc_bootstrap_config_url, "")
    ARC_GITHUB_APP_ID              = coalesce(var.arc_github_app_id, "")
    ARC_GITHUB_APP_INSTALLATION_ID = coalesce(var.arc_github_app_installation_id, "")
    ARC_GITHUB_APP_PRIVATE_KEY_SHA = var.arc_github_app_private_key_path != null ? sha256(file(var.arc_github_app_private_key_path)) : ""
    ARC_RUNNER_LABELS              = join(",", var.arc_bootstrap_runner_labels)
    ARC_RUNNER_MIN_REPLICAS        = tostring(var.arc_runner_min_replicas)
    ARC_RUNNER_MAX_REPLICAS        = tostring(var.arc_runner_max_replicas)
    ARC_RUNNER_NODEPOOL_NAME       = local.arc_runner_nodepool_name
    ARC_RUNNER_IMAGE               = var.arc_runner_image
  }

  arc_bootstrap_command = var.arc_bootstrap_script_shell == "powershell" ? "pwsh -File ${local.arc_bootstrap_script_path}" : "bash ${local.arc_bootstrap_script_path}"

  # ============================================================================
  # Managed Egress Feature Gating (T007)
  # ============================================================================

  # Validation: Exactly one egress mode must be active (T005 - Mutual Exclusivity)
  managed_egress_nat_mode_validation = (
    (var.managed_egress_enabled && !var.enable_nat_gateway) ||
    (!var.managed_egress_enabled && var.enable_nat_gateway)
  )

  # Force failure if mutual exclusivity is violated
  managed_egress_validation_check = var.managed_egress_enabled == var.enable_nat_gateway ? (
    file("ERROR: Egress mode conflict - exactly one of (managed_egress_enabled=true AND enable_nat_gateway=false) OR (managed_egress_enabled=false AND enable_nat_gateway=true) is required.")
  ) : "valid"

  # Effective outbound egress mode: either "managed_firewall" or "nat_gateway"
  effective_egress_mode = var.managed_egress_enabled ? "managed_firewall" : "nat_gateway"

  # Consolidated list of allowed FQDNs in managed egress mode (required platform + user-defined)
  managed_egress_fqdns_effective = var.managed_egress_enabled ? distinct(concat(
    var.managed_egress_required_platform_fqdns,
    var.managed_egress_allow_fqdns
  )) : []

  # Subnets eligible for managed egress UDR attachment (outbound-capable subnets)
  managed_egress_eligible_subnets = [
    "aks_nodes",
    "acr_tasks",
    "vdi_integration",
    "dev_vm"
  ]

  # Computed firewall policy name (for managed egress mode only)
  managed_egress_firewall_policy_name = var.managed_egress_enabled ? "fwpolicy-${var.prefix}-egress" : ""
}
