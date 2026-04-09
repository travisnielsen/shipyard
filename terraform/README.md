# Terraform Demo Topology

This folder contains a private-network-focused Azure topology that can deploy:

- AKS-hosted remote dev workspaces
- Azure Container Apps-hosted remote dev workspaces
- Shared supporting services (ACR + Key Vault via private endpoints)

## Structure

- `envs/demo/`: composable environment stack and variables.
- `modules/networking/`: VNet, subnets, NSGs, private DNS zones.
- `modules/platform_services/`: ACR and Key Vault with private endpoints.
- `modules/aks/`: private AKS cluster.
- `modules/container_apps/`: internal Container Apps environment and sample app.

## Deploy

```bash
cd envs/demo
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan -out demo.tfplan
terraform apply -auto-approve demo.tfplan
```

## Security Defaults

- Public network access disabled where supported.
- Private endpoints for ACR and Key Vault.
- AKS private cluster enabled.
- Container Apps environment configured as internal.
