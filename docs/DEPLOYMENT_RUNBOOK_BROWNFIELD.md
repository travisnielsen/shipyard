# Deployment Runbook (AKS Brownfield)

This document is the brownfield companion to [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md).

Use this runbook when AKS and shared platform capabilities already exist (for example: image build/publish pipelines, ACR governance, and GitHub runner setup are owned by another team).

Scope of this document:
- Create and operate per-user remote devcontainer workspaces on an existing AKS cluster.
- Validate the minimum AKS/storage/RBAC prerequisites required by the workspace scripts.

Out of scope:
- Building/publishing container images
- GitHub Actions runner controller (ARC) installation
- GitHub OIDC/federation setup
- New greenfield infrastructure deployment patterns

## 1. Brownfield Assumptions

The existing environment already provides:
- An AKS cluster reachable from an operator host
- A remote-devcontainer image available in a registry reachable by AKS
- A storage account for Azure Files-backed user workspaces
- Entra groups (or equivalent access model) for developers and operators

## 2. Prerequisites

Install and configure:
- Azure CLI (`az`)
- `kubectl`
- `kubelogin`

For private AKS clusters, run provisioning commands from a host on the private network with DNS resolution to the AKS API server endpoint.

Authenticate and select subscription:

```bash
az login
az account set --subscription "<subscription-id>"
```

## 3. Minimum AKS Baseline (Brownfield Gate)

This repository's provisioning scripts enforce the following:
- Kubernetes server version >= 1.34
- Azure Files CSI driver `file.csi.azure.com` is present
- Azure Files dynamic provisioning path is healthy:
  - AKS < 1.34: `csi-azurefile-controller` deployment exists
  - AKS >= 1.34: `csi-azurefile-node` DaemonSet has ready pods (controllerless model)

Quick verification:

```bash
kubectl version -o json
kubectl get csidriver file.csi.azure.com
kubectl get deployment csi-azurefile-controller -n kube-system || true
kubectl get daemonset csi-azurefile-node -n kube-system
```

## 4. Required Permissions

### 4.1 Operator Access

The operator identity used to provision workspaces must be able to:
- Run `az aks get-credentials --format exec`
- Query cluster-scoped CSI resources (`csidrivers.storage.k8s.io`)

If Azure RBAC for Kubernetes authorization is enabled, operators typically need:
- `Azure Kubernetes Service RBAC Cluster Admin` on the AKS cluster resource

### 4.2 Storage RBAC for AKS Identities

On the target storage account scope, ensure AKS identity permissions include:
- `Storage File Data SMB MI Admin`
- `Storage Account Contributor`
- `Storage File Data SMB Share Contributor`

At minimum, validate on kubelet identity (required by the script).
For AKS 1.34+ controllerless behavior, also validate the cluster managed identity has the same storage roles.

### 4.3 Workspace User/Operator Access Model

Typical mapping for this repo's workflow:
- Workspace users: AKS cluster user access + read access to workspace image + share access
- Workspace operators: cluster admin-level access for provisioning and support

## 5. Storage and Network Requirements

Ensure the workspace storage account is configured for MI-based Azure Files mount:
- SMB OAuth enabled (`--enable-smb-oauth true`)
- Private endpoint/DNS routing in place if cluster is private

If multiple AKS clusters exist in the current Azure context, set explicit selectors before provisioning:

```bash
export AKS_RESOURCE_GROUP="<aks-rg>"
export AKS_CLUSTER_NAME="<aks-name>"
```

## 6. Workspace Provisioning (Per User)

Run the provisioning script:

```bash
cd ops/scripts
./provision-workspace.sh "<username>" "<storage-account-rg>" "<storage-account-name>"
```

What this script does:
- Creates namespace `devcontainer-<username>`
- Ensures storage account SMB OAuth is enabled
- Creates a per-user managed-identity Azure Files `StorageClass`
- Applies `LimitRange` and `ResourceQuota`
- Creates PVC and deploys `dev-workspace`
- Waits for rollout and emits diagnostics on failure

Optional: explicitly set workspace image when auto-discovery is ambiguous.

```bash
export DEV_WORKSPACE_IMAGE="<acr-login-server>/remote-devcontainer:latest"
```

## 7. Developer Connection Flow

After workspace provisioning:

```bash
kubectl config set-context --current --namespace="devcontainer-<username>"
```

In VS Code:
1. Install `Dev Containers` and `Kubernetes` extensions.
2. Run `Dev Containers: Attach to Running Kubernetes Container...`.
3. Select AKS context, namespace, pod, and container.

For detailed end-user onboarding, see [AKS_DEVCONTAINER_ONBOARDING.md](AKS_DEVCONTAINER_ONBOARDING.md).

## 8. Day-2 Operations

### 8.1 Re-provision / Update Workspace

Re-run provisioning for the same user to reconcile namespace resources after config changes:

```bash
cd ops/scripts
./provision-workspace.sh "<username>" "<storage-account-rg>" "<storage-account-name>"
```

### 8.2 Teardown a User Workspace

```bash
cd ops/scripts
./deprovision-workspace.sh "<username>" "<storage-account-name>"
```

Delete workspace data as well:

```bash
./deprovision-workspace.sh "<username>" "<storage-account-name>" --delete-data
```

## 9. Brownfield Troubleshooting

### Symptom: provisioning fails AKS version gate
- Verify cluster is >= 1.34.
- Upgrade cluster/node pools if needed.

### Symptom: `file.csi.azure.com` missing
- Enable/repair Azure Files CSI driver on the cluster.

### Symptom: CSI checks fail with forbidden
- Operator lacks cluster-scoped Kubernetes authorization.
- Grant/verify AKS RBAC role and refresh credentials.

### Symptom: PVC remains Pending
- Validate storage RBAC on AKS kubelet identity (and cluster identity on 1.34+).
- Validate private endpoint and DNS resolution to `privatelink.file.core.windows.net` if using private networking.

### Symptom: pod not scheduled
- Verify node pool labels/taints satisfy workload selector/toleration expectations.

### Symptom: VS Code cannot find pod
- Ensure current kubectl namespace is set to `devcontainer-<username>`.

## 10. References

- Greenfield + full platform runbook: [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md)
- End-user onboarding: [AKS_DEVCONTAINER_ONBOARDING.md](AKS_DEVCONTAINER_ONBOARDING.md)
- Day-2 operations notes: [DAY2_OPERATIONS.md](DAY2_OPERATIONS.md)
- Provision script: [ops/scripts/provision-workspace.sh](../ops/scripts/provision-workspace.sh)
- Deprovision script: [ops/scripts/deprovision-workspace.sh](../ops/scripts/deprovision-workspace.sh)
