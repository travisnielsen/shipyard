# Devcontainer Package

This folder contains a deployable package for remote development workspaces — a shared container image that targets **AKS** with per-user namespace isolation.

## Contents

- `Dockerfile`: base image with common dev tools and the `code` CLI for tunnels.
- `scripts/start-vscode-server.sh`: entrypoint — runs `idle` (default) or `code tunnel` depending on `START_MODE`.
- `scripts/healthcheck.sh`: readiness probe, mode-aware.
- `scripts/provision-workspace.sh`: per-user AKS namespace provisioning.
- `scripts/provision-workspace.ps1`: PowerShell equivalent of the per-user AKS provisioning flow.
- `scripts/deprovision-workspace.sh`: per-user AKS namespace teardown.
- `scripts/deprovision-workspace.ps1`: PowerShell equivalent of the per-user AKS teardown flow.
- `manifests/`: Kubernetes manifests (namespace, MI-backed StorageClass template, PVC, Deployment, quotas).

## Build

Build in Azure Container Registry to guarantee a Linux amd64 image regardless of local machine architecture:

Prerequisites:
- Your identity (or group) has `AcrPush` on the registry.
- Registry allows trusted Azure services for ACR Tasks (`network_rule_bypass_option = "AzureServices"` in Terraform).

```bash
az acr build \
  --registry <acr-name> \
  --image remote-devcontainer:latest \
  --platform linux/amd64 \
  .
```

To pin a specific `code-server` version during ACR build:

```bash
When attaching from VS Code, set the current kubectl namespace to the workspace namespace first. The Dev Containers extension queries the current kubectl namespace and will not discover the pod if kubectl is still pointed at `default`.

```bash
kubectl config set-context --current --namespace=devcontainer-<username>
```
az acr build \
  --registry <acr-name> \
  --image remote-devcontainer:latest \
  --platform linux/amd64 \
  --build-arg CODE_SERVER_VERSION=4.115.0 \
  .
```

## Run Locally

```bash
# VS Code Remote Tunnels (identity-based auth)
docker run --rm -it \
  -e START_MODE=tunnel \
  -e TUNNEL_NAME=my-local-test \
  remote-devcontainer:latest
```

Open the printed `vscode.dev` URL in VS Code (Remote - Tunnels extension) or a browser.

## Provision a User Workspace

For private AKS clusters, run provisioning from the private dev VM (or another host with private network + DNS access to the AKS API endpoint).

```bash
./scripts/provision-workspace.sh <username> <storage-resource-group> <storage-account-name>
```

PowerShell:

```powershell
./scripts/provision-workspace.ps1 <username> <storage-resource-group> <storage-account-name>
```

Fail-fast checks are enforced before provisioning:
- Kubernetes server version must be >= 1.34
- `file.csi.azure.com` CSI driver must be present
- AKS kubelet identity must already have `Storage File Data SMB MI Admin` on the storage account

If your Azure context contains multiple AKS clusters, set:

```bash
export AKS_RESOURCE_GROUP=<aks-rg>
export AKS_CLUSTER_NAME=<aks-name>
```

### Teardown

```bash
./scripts/deprovision-workspace.sh <username> <storage-account-name>               # keep data
./scripts/deprovision-workspace.sh <username> <storage-account-name> --delete-data # delete Azure File Share too
```

PowerShell:

```powershell
./scripts/deprovision-workspace.ps1 <username> <storage-account-name>
./scripts/deprovision-workspace.ps1 <username> <storage-account-name> -DeleteData
```

---

## Architecture & Connection

The container image runs on AKS with per-user namespace isolation.

- **Isolation unit:** Namespace per user
- **Storage:** Dynamic PV/PVC via Azure Files CSI driver with managed identity (no Kubernetes storage secrets)
- **Connection:** `Dev Containers: Attach to Running Kubernetes Container...` — VS Code Server auto-installs in the pod; no internet required from the pod
- **Runtime mode:** `START_MODE=idle` (attach-first model)
- **Resource governance:** PSA (`enforce: baseline`) + ResourceQuota + LimitRange per namespace
- **Kubernetes API access:** Full via `kubectl`
- **Identity:** Entra ID via AKS RBAC/kubelogin

## CI/CD Pattern

The container image is built and pushed to ACR:

```text
git push → GitHub Actions
  └─ az acr build --platform linux/amd64 (tagged with SHA + latest)

Per-user provisioning:
  ./scripts/provision-workspace.sh <username> <storage-rg> <storage-account>
```

The Terraform demo topology provisions the shared infrastructure (VNet, ACR, Key Vault, AKS cluster) via Terraform. Per-user workspaces are lifecycle-managed outside Terraform by the provision/deprovision scripts.

