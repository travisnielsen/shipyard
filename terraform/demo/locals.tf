locals {
  # Create unique identifier for DNS-sensitive resources (storage, ACR)
  # Format: <single-letter><5-random-lowercase-alphanumeric>
  # Example: a1b2c3
  identifier = "${random_string.alpha_prefix.result}${random_string.naming.result}"

  deploy_aks = true

  # Utility VM setup script aligned with Cadence bootstrap.
  utility_vm_setup_script = file("${path.module}/scripts/util_vm_setup_choco.ps1")
}
