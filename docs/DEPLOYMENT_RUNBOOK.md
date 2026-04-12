# Deployment Runbook (AKS)

This document is a generic, step-by-step reference pattern for deploying and operating remote development workspaces on:

- Azure Kubernetes Service (AKS)

It assumes this repository layout:

- `infra` for shared platform infrastructure
- `devcontainer` for image build and in-container runtime scripts
- `ops/scripts` for control-plane provisioning and bootstrap scripts

## 1. Prerequisites

Install and configure the following tools:

- Azure CLI (`az`)
- Terraform (compatible with `infra/versions.tf`)
- Docker
- `kubectl` (for AKS workflow)

For private AKS clusters, run AKS provisioning commands from a host on the private network (for example the utility/dev VM deployed in this environment). External WSL/laptop shells without private DNS + network path to the AKS API endpoint will fail.

Authenticate to Azure and select a subscription:

```bash
az login
az account set --subscription "<subscription-id>"
```

## 2. Configure Entra ID

### 2.1 Create Application Groups

Create or reuse the Entra groups used by Shipyard.

Developers:

- Purpose: users who launch and use dev containers
- Output to capture: group object ID for later `workspace_user_group_id` assignment

```powershell
cd ops/scripts
./create-workspace-group.ps1 "shipyard-workspace-users" "" "workspace-user"
```

Shipyard operators:

- Purpose: platform operators who provision and administer workspaces
- Output to capture: group object ID for later `workspace_operator_group_id` assignment
- This one group receives both AKS admin roles plus the platform-level assignments defined in Terraform

```powershell
cd ops/scripts
./create-workspace-group.ps1 "shipyard-operators" "" "workspace-operator"
```

### 2.2 Create Federated Credentials For GitHub Actions

Run one of the federation scripts from `ops/scripts` and capture the emitted values:

```bash
cd ops/scripts
./setup-github-actions.sh <subscription-id> <github-owner> <github-repo>
```

```powershell
cd ops/scripts
./setup-github-actions.ps1 <subscription-id> <github-owner> <github-repo>
```

> [!Note]
> Be sure to keep a copy of the script output as the information will be needed for future steps.

Subject claim guidance:

- Branch-specific: `repo:<owner>/<repo>:ref:refs/heads/main`
- Environment-specific: `repo:<owner>/<repo>:environment:<environment-name>`

Least-privilege mapping for federation identity:

| Scope | Role | Purpose |
| --- | --- | --- |
| ACR resource (preferred) | `AcrPull` | Pull devcontainer image for runner and workloads |
| ACR resource (only if publishing) | `AcrPush` | Push devcontainer image from CI |
| AKS resource group (optional) | `Reader` | Metadata discovery for scripts/workflows |

## 3. Configure Terraform Variables

After completing Section 2, populate local Terraform variables with the IDs and emitted values you captured.

### 3.1 Populate Terraform Inputs

Create your local Terraform variable file:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Set the identity-driven values from Section 2:

```hcl
workspace_user_group_id     = "<developers-group-object-id>"
workspace_operator_group_id = "<shipyard-operators-group-object-id>"
arc_runtime_principal_id    = "<ARC_RUNTIME_PRINCIPAL_ID-from-script-output>"
```

`ARC_RUNTIME_PRINCIPAL_ID` is the service principal object ID (RBAC principal ID), not the client ID.

Review the remaining Terraform values in `infra/terraform.tfvars`:

- `prefix`
- `location`
- `resource_group_name`
- `dev_vm_admin_password`
- `workspace_user_group_id`
- `workspace_operator_group_id`
- `arc_runtime_principal_id`
- `subnet_cidrs` (if custom network ranges are required)

## 4. Deploy Shared Infrastructure

The Terraform deployment scripts use `local-exec` commands to provision the GitHub Actions Runner Controller (ARC) to the AKS cluster. This introduces the following prerequisites:

- `az` installed on the Terraform execution host
- authenticated `az login` context with target subscription access
- outbound access to Azure control plane APIs
- `pwsh` installed if `arc_bootstrap_script_shell = "powershell"`

From `infra`:

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

## 5. Configure GitHub Actions Repository Variables

This section must be completed after Section 4 because `ACR_LOGIN_SERVER` comes from Terraform output.

Set the required repository variables for `.github/workflows/devcontainer-image-cd.yml`:

- `AZURE_CLIENT_ID` (from `setup-github-actions` script output)
- `AZURE_TENANT_ID` (from `setup-github-actions` script output)
- `AZURE_SUBSCRIPTION_ID` (from `setup-github-actions` script output)
- `ACR_LOGIN_SERVER` (from `terraform output acr_login_server`)

Example command to capture the ACR value:

```bash
cd infra
terraform output -raw acr_login_server
```

## 6. Build and Publish the Workspace Image With GitHub Actions

Preferred path: use `.github/workflows/devcontainer-image-cd.yml` to build and push the devcontainer image from GitHub Actions. This avoids requiring direct access to the private deployment environment.

Workflow file: `.github/workflows/devcontainer-image-cd.yml`

Before triggering the workflow, confirm Section 5 is complete and these repository variables are set:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `ACR_LOGIN_SERVER`

Workflow behavior:

- Triggers on `push` changes under `devcontainer/**`
- Triggers on `pull_request` changes under `devcontainer/**`
- Uses OIDC via `azure/login@v2`
- Builds the image as `${ACR_LOGIN_SERVER}/remote-devcontainer:${GITHUB_SHA}`
- Pushes an additional `${branch}-${GITHUB_SHA}` tag for branch refs

Recommended execution flow:

1. Commit a change under `devcontainer/`.
2. Push the branch to GitHub.
3. Monitor the `devcontainer-image-cd` workflow run.
4. Confirm the image was published to ACR.

Validation:

- Confirm workflow variables pass the `Validate required variables` step.
- Confirm `Azure login (OIDC)` succeeds.
- Confirm image tags are pushed to ACR.
- Confirm the workflow summary includes the published image reference.

Failure handling:

- Missing `AZURE_*` or `ACR_LOGIN_SERVER` repository variables fails the workflow immediately.
- ACR auth or push failures fail closed with a non-zero exit code.

## 7. Manual Image Build and Push (optional)

Use this path only when GitHub Actions cannot be used. It requires access to the private environment and local deployment tooling, which is not the preferred operating model.

Before running the manual build, ensure both prerequisites are met:

- Your signed-in identity (or group) has `AcrPush` on the ACR.
- ACR trusted-services bypass is enabled (`network_rule_bypass_option = "AzureServices"`) for locked-down registries.

Build directly in Azure Container Registry to guarantee a Linux amd64 image (recommended for ARM developer machines):

```bash
az acr build \
  --registry "<acr-name>" \
  --image "remote-devcontainer:latest" \
  --platform linux/amd64 \
  ./devcontainer
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

## 8. AKS User Workspace (Per User)

### 8.1 Get AKS Credentials

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

### 8.2 Provision a User Workspace

```bash
cd ops/scripts
./provision-workspace.sh "<username>" "<storage-account-rg>" "<storage-account-name>"
```

This script enforces fail-fast checks (AKS version, CSI driver, required RBAC role).

`workspace_user_group_id` receives AKS Cluster User + AcrPull + Storage File Data SMB Share Contributor.

`workspace_operator_group_id` receives Azure Kubernetes Service Cluster Admin Role and Azure Kubernetes Service RBAC Cluster Admin for cluster-scoped provisioning and administration operations.

### 8.3 Connect to Workspace

Use VS Code with Kubernetes + Dev Containers extensions:

- Set the current kubectl namespace to the workspace namespace first:

```bash
kubectl config set-context --current --namespace="devcontainer-<username>"
```

- Command Palette: `Dev Containers: Attach to Running Kubernetes Container...`
- Select pod in namespace: `devcontainer-<username>`

The Dev Containers extension discovers pods from the current kubectl namespace. If kubectl is still pointed at `default`, VS Code may report that no pods were found.

## 9. Teardown

### 9.1 Remove a User Workspace

```bash
cd ops/scripts
./deprovision-workspace.sh "<username>" "<storage-account-name>"
```

Delete user data as well:

```bash
./deprovision-workspace.sh "<username>" "<storage-account-name>" --delete-data
```

### 9.2 Destroy Shared Infrastructure

```bash
cd infra
terraform destroy
```

## 10. Quick Troubleshooting

- AKS provisioning fails on prerequisites:
  - Verify cluster version, CSI driver presence, and kubelet role assignment.
- Image pull failures:
  - Verify ACR role assignments and pushed image tags.
- `az acr build` fails with `403 Forbidden` while logging into registry:
  - Verify ACR trusted-services bypass is enabled (`network_rule_bypass_option = "AzureServices"`).
  - Verify caller has `AcrPush` on the registry.
- Storage mount issues:
  - Confirm storage account outputs used in provisioning scripts are correct.

## 11. Troubleshooting Matrix

| Symptom | Likely Cause | Verification | Remediation |
| --- | --- | --- | --- |
| `terraform_data.arc_bootstrap` fails | Missing Azure auth or CLI on execution host | Check Terraform stderr and `az account show` | Install CLI and re-authenticate, then re-apply |
| ARC controller pods not ready | Helm install failure or cluster dependency issue | `kubectl get pods -n arc-systems` | Re-run apply after correcting chart/version or cluster connectivity |
| Runner pods pending | Node selector/taint mismatch | `kubectl describe pod -n arc-runners <pod>` | Align `nodeSelector` and tolerations with runner pool labels/taints |
| Runner pool not reaching min=0 | Environment does not support user pool zero-min | Check tfvars `arc_runner_nodepool_scale_to_zero_supported` | Set support flag false and document effective min fallback |
| Devcontainer CD workflow fails at Azure login | OIDC app or subject claim mismatch | Review workflow logs and federation script output | Re-run setup script with correct subject claim pattern |
| Devcontainer CD workflow fails push | Missing `AcrPush` for federation principal | Inspect role assignments at ACR scope | Ensure `arc_runtime_principal_id` is set and re-apply Terraform |

## 12. Staged Deployment Guide

### Stage 1: Entra + GitHub Federation

1. Run federation setup script from `ops/scripts`.
2. Record emitted `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` for Section 5.
3. Validate with a minimal workflow step using `azure/login@v2` and `az account show`.

### Stage 2: Infrastructure + ARC Bootstrap

1. Set Terraform variables for ARC bootstrap and runner node pool.
2. Run `terraform init`, `terraform validate`, `terraform plan`, `terraform apply` in `infra`.
3. Validate:
   - `terraform output arc_runner_nodepool_name`
   - `az aks command invoke ... kubectl get pods -n arc-systems`
   - `az aks command invoke ... kubectl get autoscalingrunnersets -n arc-runners`

### Stage 3: Private-Agent Devcontainer Build/Push

1. Ensure `.github/workflows/devcontainer-image-cd.yml` is present.
2. Complete Section 5 and set all required repository variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACR_LOGIN_SERVER`).
3. Commit a change under `devcontainer/` and push.
4. Validate published tags in ACR and workflow job summary.

### Stage Validation Checklist

- Stage 1 complete: OIDC login succeeds with no client secret.
- Stage 2 complete: ARC controller ready and runner set reconciled.
- Stage 3 complete: image published to ACR from path-scoped workflow trigger.

## 13. Reference Files

- Terraform stack: `infra`
- Devcontainer package: `devcontainer`
- Day-2 operations: `docs/DAY2_OPERATIONS.md`
- AKS provision script: `ops/scripts/provision-workspace.sh`
- AKS teardown script: `ops/scripts/deprovision-workspace.sh`
