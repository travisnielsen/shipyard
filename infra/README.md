# Terraform Demo Topology

This folder contains a private-network-focused Azure topology that can deploy:

- AKS-hosted remote dev workspaces
- Azure Container Apps-hosted remote dev workspaces
- Shared supporting services (ACR + Key Vault via private endpoints)
- Isolated workload VM for testing remote dev container access

## Structure

- `demo/`: composable environment stack and variables.
- Uses Terraform AVM modules directly from the Azure namespace for:
  - Virtual network and subnets
  - Private DNS zones
  - Container Registry and Key Vault
  - AKS managed cluster
  - Container Apps managed environment and app
  - Log Analytics workspace
  - Dedicated test VM subnet + Windows VM + Custom Script Extension bootstrap + Azure Bastion

## AVM Module Versions

All modules are pinned to exact versions. To upgrade, update the `version` constraint in `main.tf`, run `terraform init -upgrade`, and re-validate.

| Module | Source | Pinned Version | Registry |
|---|---|---|---|
| Virtual Network | `Azure/avm-res-network-virtualnetwork/azurerm` | `0.17.1` | [link](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.17.1) |
| Private DNS Zone | `Azure/avm-res-network-privatednszone/azurerm` | `0.5.0` | [link](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm/0.5.0) |
| Container Registry | `Azure/avm-res-containerregistry-registry/azurerm` | `0.5.1` | [link](https://registry.terraform.io/modules/Azure/avm-res-containerregistry-registry/azurerm/0.5.1) |
| Key Vault | `Azure/avm-res-keyvault-vault/azurerm` | `0.10.2` | [link](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm/0.10.2) |
| AKS Managed Cluster | `Azure/avm-res-containerservice-managedcluster/azurerm` | `0.5.3` | [link](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm/0.5.3) |
| Container Apps Env | `Azure/avm-res-app-managedenvironment/azurerm` | `0.4.0` | [link](https://registry.terraform.io/modules/Azure/avm-res-app-managedenvironment/azurerm/0.4.0) |
| Container App | `Azure/avm-res-app-containerapp/azurerm` | `0.8.0` | [link](https://registry.terraform.io/modules/Azure/avm-res-app-containerapp/azurerm/0.8.0) |
| Log Analytics Workspace | `Azure/avm-res-operationalinsights-workspace/azurerm` | `0.5.1` | [link](https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm/0.5.1) |

## Deploy

```bash
cd demo
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan -out demo.tfplan
terraform apply -auto-approve demo.tfplan
```

Before `terraform plan`, create (or resolve) the Entra groups used for workspace access and provisioning, then copy the printed object IDs into `terraform.tfvars`:

```powershell
./scripts/create-workspace-group.ps1 "shipyard-workspace-users" "" "workspace-user"
./scripts/create-workspace-group.ps1 "shipyard-workspace-cluster-admins" "" "workspace-cluster-admin"
```

## Security Defaults

- Public network access disabled where supported.
- Private endpoints for ACR and Key Vault.
- AKS private cluster enabled.
- Container Apps environment configured as internal.
- Dedicated subnet (`dev_vm`) for test VM network isolation.
- Dedicated `AzureBastionSubnet` for Bastion-hosted administrative access.

## Test VM Notes

- VM provisioning is controlled by `deploy_test_vm` (default `true`).
- Post-provision software install is executed by `azurerm_virtual_machine_extension` (`CustomScript`).
- Bootstrap script path: `infra/demo/scripts/util_vm_setup_choco.ps1`.
- Required variable: `dev_vm_admin_password`.
- Connect using Azure Bastion (RDP over TLS) to avoid exposing VM public IP.
