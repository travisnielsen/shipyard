# shipyard Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-16

## Active Technologies
- HCL / Terraform >= 1.10.0 (bumped from 1.9 — required by `avm-res-compute-virtualmachine` v0.20.0) (002-avd-infrastructure)
- N/A (no application data storage; admin credentials in Azure Key Vault) (002-avd-infrastructure)

- Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values + Azure CLI (`az`), `kubectl`, `helm`, GitHub Actions (`azure/login`), ARC Helm charts (001-add-aks-arc-cd)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values

## Code Style

Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values: Follow standard conventions

## Recent Changes
- 002-avd-infrastructure: Added HCL / Terraform >= 1.10.0 (bumped from 1.9 — required by `avm-res-compute-virtualmachine` v0.20.0)

- 001-add-aks-arc-cd: Added Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values + Azure CLI (`az`), `kubectl`, `helm`, GitHub Actions (`azure/login`), ARC Helm charts

<!-- MANUAL ADDITIONS START -->

## AKS Platform Notes

The AKS cluster runs Kubernetes 1.34+. Scripts and Terraform must account for
these version-specific behaviors:

| Behavior | AKS < 1.34 | AKS >= 1.34 |
|---|---|---|
| Azure File CSI controller | Separate `csi-azurefile-controller` Deployment in kube-system | **Controllerless** — controller sidecar embedded in `csi-azurefile-node` DaemonSet pods. No standalone controller Deployment exists. |
| CSI driver identity for storage ops | Kubelet (agentpool) managed identity | **Cluster managed identity** — the cluster MI (not kubelet) performs file share create/delete. Both identities need storage RBAC roles. |
| Required RBAC on storage account | `Storage Account Contributor` + `Storage File Data SMB Share Contributor` on kubelet MI | Same roles on **both** the kubelet MI **and** the cluster MI. |

**Before writing or modifying any script that interacts with AKS resources**:
1. Run `kubectl version -o json` to confirm the server version.
2. Do **not** assume `csi-azurefile-controller` Deployment exists — check for the
   DaemonSet `csi-azurefile-node` in kube-system as the fallback.
3. When assigning storage RBAC, include the cluster identity
   (`az aks show --query identity.principalId`) in addition to the kubelet identity.

<!-- MANUAL ADDITIONS END -->
