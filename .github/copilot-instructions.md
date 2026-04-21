# shipyard Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-16

## Active Technologies
- HCL / Terraform >= 1.10.0 (bumped from 1.9 — required by `avm-res-compute-virtualmachine` v0.20.0) (002-avd-infrastructure)
- N/A (no application data storage; admin credentials in Azure Key Vault) (002-avd-infrastructure)

- Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values + Azure CLI (`az`), `kubectl`, `helm`, GitHub Actions (`azure/login`), ARC Helm charts (001-add-aks-arc-cd)

## Project Structure

```text
infra/                              # Infrastructure as Code (Terraform)
  main.tf                           # Foundation: resource group, naming, state migration
  networking.tf                     # VNet, subnets, NAT, private DNS zones
  devops.tf                         # Container Registry (ACR)
  security-services.tf              # Key Vault (shared secrets)
  data.tf                           # Storage account & Azure Files
  utilities.tf                      # Dev VM, Bastion (test infrastructure)
  aks.tf                            # Kubernetes cluster & workload identities
  avd.tf                            # Azure Virtual Desktop & session hosts
  arc-bootstrap.tf                  # ARC CI/CD orchestration
  rbac.tf                           # All role assignments (centralized by principal type)
  
  providers.tf                      # Provider configuration (azurerm, azapi, modtm, random, tls, time)
  versions.tf                       # Version constraints
  variables.tf                      # Input variables
  outputs.tf                        # Output values
  locals.tf                         # Local values & computed state
  avd_variables.tf                  # AVD-specific variables

devcontainer/                       # Dev container configuration
docs/                               # Documentation & runbooks
ops/                                # Operational scripts
specs/                              # Feature specifications & planning
```

## Terraform File Organization Rules

**File Organization Pattern**: Split by service/concern domain, **not** by resource type.

### File Responsibilities:
- **main.tf**: Foundation only — resource group, random naming, state migration markers. No service resources.
- **networking.tf**: Virtual network fabric, subnets, NAT, private DNS zones (all 3 zones defined here).
- **devops.tf**: Container Registry (ACR) + optional task agent pool.
- **security-services.tf**: Key Vault (shared secrets store).
- **data.tf**: Storage account + Azure Files configuration.
- **utilities.tf**: Test/workload infrastructure — dev VM, Bastion.
- **aks.tf**: AKS cluster, node pools, cluster-managed identity (control-plane identity).
- **avd.tf**: Azure Virtual Desktop — host pool, app groups, workspace, session hosts, AVD-specific Key Vault.
- **arc-bootstrap.tf**: ARC platform bootstrap orchestration (small, focused).
- **rbac.tf**: **Centralized RBAC** — all 24+ `azurerm_role_assignment` resources organized by principal type (AKS workloads, AVD service principals, workspace operators, users, current principal, ARC runtime, GitHub OIDC).
- **providers.tf, versions.tf, variables.tf, outputs.tf, locals.tf**: Configuration & declarations (unchanged across refactors).

### Module Dependencies:
- All modules depend on `azurerm_resource_group.this` in main.tf.
- `module.networking` is foundational; all other services depend on its subnets (e.g., `module.networking.subnets["aks_nodes"]`).
- Private DNS zones are defined in `networking.tf` but referenced by service modules (`devops.tf`, `security-services.tf`, `data.tf`, `avd.tf`).
- `rbac.tf` references service identities/resources but has no terraform dependencies (loose coupling).

### When Adding a New Service:
1. **Determine the domain**: Is it infrastructure (network, storage), compute (VMs, AKS), platform (AVD, ARC), or operational (scripts, bootstrap)?
2. **Follow naming convention**: Create a file named after the service (e.g., `cosmosdb.tf` for Azure Cosmos DB, `postgres.tf` for managed PostgreSQL).
3. **If placement is ambiguous**, ask the user for clarification:
   - *"This service could fit in either [option A] or [option B]. Which file would you prefer? Or should I create a new file?"*
   - Example: *"Does this API Management instance belong in `devops.tf` (API/platform tooling) or should it have its own `apim.tf`?"*
4. **Declare dependencies on `networking.tf` subnets** if needed (private endpoints, VNet integration).
5. **Add RBAC assignments to `rbac.tf`** (never scatter role assignments across domain files).
6. **Update this section** if a new stable domain emerges (e.g., data tier services warrant a separate file).

## Commands

# Add commands for Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values

## Code Style

**Terraform**: 
- Use Azure Verified Modules (AVM) only — no custom module wrappers in infra/.
- Follow AVM input shapes exactly (e.g., storage_profile nested structure for AKS).
- Organize resources by domain concern; use comments to section related resources.
- Centralize RBAC — all role assignments belong in `rbac.tf` organized by principal type (see RBAC sections with headers).
- Centralize private DNS zones in `networking.tf`; reference from domain files via module outputs.
- Use local variables (locals.tf) for computed values; avoid repeating logic.

**YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values**: Follow standard conventions

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
