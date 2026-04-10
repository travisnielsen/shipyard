# Deployment Runbook (AKS)

This document is a generic, step-by-step reference pattern for deploying and operating remote development workspaces on:

- Azure Kubernetes Service (AKS)

It assumes this repository layout:

- `terraform/demo` for shared platform infrastructure
- `devcontainer-package` for image build and per-user provisioning scripts

## 1. Prerequisites

Install and configure the following tools:

- Azure CLI (`az`)
- Terraform (compatible with `terraform/demo/versions.tf`)
- Docker
- `kubectl` (for AKS workflow)

For private AKS clusters, run AKS provisioning commands from a host on the private network (for example the utility/dev VM deployed in this environment). External WSL/laptop shells without private DNS + network path to the AKS API endpoint will fail.

Authenticate to Azure and select a subscription:

```bash
az login
az account set --subscription "<subscription-id>"
```

## 2. Configure Terraform Inputs

1. Go to the Terraform demo directory.
2. Create your local variable file from the example.
3. Edit values for your environment.

```bash
cd terraform/demo
cp terraform.tfvars.example terraform.tfvars
```

Minimum values to review in `terraform.tfvars`:

- `prefix`
- `location`
- `resource_group_name`
- `dev_vm_admin_password`
- `subnet_cidrs` (if custom network ranges are required)

## 3. Deploy Shared Infrastructure

From `terraform/demo`:

```bash
terraform init
terraform validate
terraform plan -out demo.tfplan
terraform apply -auto-approve demo.tfplan
```

Capture outputs for later steps:

```bash
terraform output
```

Commonly used outputs:

- `acr_login_server`
- `storage_account_name`
- `storage_account_resource_group`
- `aks_cluster_name`

## 4. Build and Publish the Workspace Image

Before running the build, ensure both prerequisites are met:

- Your signed-in identity (or group) has `AcrPush` on the ACR.
- ACR trusted-services bypass is enabled (`network_rule_bypass_option = "AzureServices"`) for locked-down registries.

Build directly in Azure Container Registry to guarantee a Linux amd64 image (recommended for ARM developer machines):

```bash
az acr build \
  --registry "<acr-name>" \
  --image "remote-devcontainer:latest" \
  --platform linux/amd64 \
  ./devcontainer-package
```

If you need a manual RBAC grant for the current user:

```bash
ACR_ID=$(az acr show --name "<acr-name>" --query id -o tsv)
ME_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --assignee-object-id "$ME_OBJECT_ID" \
  --assignee-principal-type User \
  --role AcrPush \
  --scope "$ACR_ID"
```

## 5. AKS User Workspace (Per User)

### 5.1 Get AKS Credentials

Run this from the private dev VM (or another host with private network + DNS access to the AKS API endpoint).

```bash
az aks get-credentials \
  --resource-group "<resource-group>" \
  --name "<aks-cluster-name>" \
  --overwrite-existing
```

If your Azure context contains multiple AKS clusters, set explicit selectors before provisioning:

```bash
export AKS_RESOURCE_GROUP="<aks-rg>"
export AKS_CLUSTER_NAME="<aks-name>"
```

### 5.2 Provision a User Workspace

```bash
cd devcontainer-package
./scripts/provision-workspace.sh "<username>" "<storage-account-rg>" "<storage-account-name>"
```

This script enforces fail-fast checks (AKS version, CSI driver, required RBAC role).

### 5.3 Connect to Workspace

Use VS Code with Kubernetes + Dev Containers extensions:

- Set the current kubectl namespace to the workspace namespace first:

```bash
kubectl config set-context --current --namespace="devcontainer-<username>"
```

- Command Palette: `Dev Containers: Attach to Running Kubernetes Container...`
- Select pod in namespace: `devcontainer-<username>`

The Dev Containers extension discovers pods from the current kubectl namespace. If kubectl is still pointed at `default`, VS Code may report that no pods were found.

## 6. Day-2 Operations

### 6.1 Update Workspace Image

1. Rebuild in ACR and push a new image tag.
2. Re-run user provisioning script to roll updates.

## 7. Teardown

### 7.1 Remove a User Workspace

```bash
cd devcontainer-package
./scripts/deprovision-workspace.sh "<username>" "<storage-account-name>"
```

Delete user data as well:

```bash
./scripts/deprovision-workspace.sh "<username>" "<storage-account-name>" --delete-data
```

### 7.2 Destroy Shared Infrastructure

```bash
cd terraform/demo
terraform destroy
```

## 8. Quick Troubleshooting

- AKS provisioning fails on prerequisites:
  - Verify cluster version, CSI driver presence, and kubelet role assignment.
- Image pull failures:
  - Verify ACR role assignments and pushed image tags.
- `az acr build` fails with `403 Forbidden` while logging into registry:
  - Verify ACR trusted-services bypass is enabled (`network_rule_bypass_option = "AzureServices"`).
  - Verify caller has `AcrPush` on the registry.
- Storage mount issues:
  - Confirm storage account outputs used in provisioning scripts are correct.

## 9. Reference Files

- Terraform stack: `terraform/demo`
- Devcontainer package: `devcontainer-package`
- AKS provision script: `devcontainer-package/scripts/provision-workspace.sh`
- AKS teardown script: `devcontainer-package/scripts/deprovision-workspace.sh`
