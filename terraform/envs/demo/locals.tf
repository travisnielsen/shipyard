locals {
  deploy_aks            = contains(var.deploy_targets, "aks")
  deploy_container_apps = contains(var.deploy_targets, "container_apps")
}
