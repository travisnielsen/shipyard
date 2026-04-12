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
    ARC_BOOTSTRAP_EXECUTION_MODE = var.arc_bootstrap_execution_mode
    ARC_RUNNER_SCOPE             = var.arc_bootstrap_runner_scope
    ARC_RUNNER_CONFIG_URL        = coalesce(var.arc_bootstrap_config_url, "")
    ARC_RUNNER_LABELS            = join(",", var.arc_bootstrap_runner_labels)
    ARC_RUNNER_MIN_REPLICAS      = tostring(var.arc_runner_min_replicas)
    ARC_RUNNER_MAX_REPLICAS      = tostring(var.arc_runner_max_replicas)
    ARC_RUNNER_NODEPOOL_NAME     = local.arc_runner_nodepool_name
  }

  arc_bootstrap_command = var.arc_bootstrap_script_shell == "powershell" ? "pwsh -File ${local.arc_bootstrap_script_path}" : "bash ${local.arc_bootstrap_script_path}"
}
