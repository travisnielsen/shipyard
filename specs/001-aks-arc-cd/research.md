# Research: AKS ARC GitHub Build Agents

## Decision 1: Use Actions Runner Controller (ARC) Helm deployment in AKS

- Decision: Deploy ARC into the existing AKS cluster using the upstream Helm charts and manage values/manifests in-repo.
- Rationale: ARC is the standard GitHub pattern for Kubernetes-hosted private runners, supports autoscaling runner sets, and aligns with the existing AKS foundation in `infra`.
- Alternatives considered:
  - Container Apps runners: rejected due to control/feature constraints for advanced private agent scenarios.
  - Static self-hosted VM runners: rejected due to lower elasticity and higher ops overhead.

## Decision 2: Use Entra ID OIDC federation for GitHub Actions auth to Azure

- Decision: Use Terraform-managed identity/resource configuration plus idempotent setup scripts to provision app registration/service principal, federated credential subject mapping to this repository, and least-privilege RBAC assignments.
- Rationale: Avoids long-lived secrets, matches constitution identity/security requirements, and follows current Azure+GitHub best practice.
- Alternatives considered:
  - Client secret-based service principal auth: rejected due to secret management risk and policy non-compliance.
  - Managed identity only: rejected because GitHub-hosted identity requires federation trust into Entra.

## Decision 3: Build devcontainer image with path-scoped GitHub workflow and publish to deployment ACR

- Decision: Keep ACR configuration in Terraform and add a workflow triggered by `devcontainer/**` changes that authenticates with OIDC and publishes image to the existing ACR login server.
- Rationale: Limits builds to relevant changes, keeps workspace images current, and supports repeatable release behavior.
- Alternatives considered:
  - Build on every push: rejected due to unnecessary cost/runtime.
  - Manual image build only: rejected due to stale image risk and operational burden.

## Decision 4: Move control-plane workspace lifecycle scripts to top-level `ops/scripts`

- Decision: Relocate `provision-workspace.*` and `deprovision-workspace.*` from `devcontainer/scripts` to `ops/scripts`; keep in-container runtime scripts in `devcontainer/scripts`.
- Rationale: Clarifies responsibility boundaries for operators and coding agents; prevents control-plane automation from being conflated with container runtime assets.
- Alternatives considered:
  - Keep mixed script model in `devcontainer/scripts`: rejected for ambiguity.
  - Move to `infra/scripts`: rejected because infra helper scripts and workspace lifecycle scripts are different operational layers.

## Decision 5: Enforce validation through local hooks and CI checks

- Decision: Continue local hook enforcement and require workflow-level validation for Terraform and Kubernetes changes associated with this feature.
- Rationale: Reduces drift from standards, catches misconfigurations early, and aligns with constitution automation standards.
- Alternatives considered:
  - CI-only enforcement: rejected because local feedback cycle is slower.
  - Local-only enforcement: rejected because client-side hooks can be bypassed.

## Decision 6: Avoid jump-server dependency for ARC bootstrap in private AKS

- Decision: Implement bootstrap through Azure control-plane execution (`az aks command invoke`) and/or GitOps in-cluster reconciliation, avoiding dedicated jump-host infrastructure.
- Rationale: Meets private AKS requirements while eliminating operational burden and security overhead of persistent private compute used only for setup.
- Alternatives considered:
  - Dedicated jump server for `kubectl`/`helm`: rejected due to extra cost, hardening overhead, and lifecycle management burden.
  - Temporarily exposing public AKS API endpoint: rejected due to private-by-default networking posture.

## Decision 7: Use a dedicated runner node pool with explicit placement policy

- Decision: Add a dedicated AKS user node pool for ARC runner workloads and require ARC pod scheduling via node labels + taints/tolerations.
- Rationale: Current repository config taints the existing user pool for `devworkspace` workloads, so runner placement is not guaranteed without explicit placement policy. Dedicated pool reduces contention with workspace workloads and improves reliability.
- Alternatives considered:
  - Reuse existing `devworkspace` user pool: rejected due to scheduling ambiguity and workload contention.
  - Run runners on system pool: rejected to avoid mixing platform and build workloads.

## Decision 8: Bootstrap option defaults and fallback order

- Decision: Default bootstrap path is Terraform-orchestrated post-provision script execution from `ops/scripts` using Azure control-plane commands (`az aks command invoke`). Secondary path is GitOps reconciliation from cluster-installed controllers.
- Rationale: This preserves a single operator flow, keeps bootstrap logic in repository scripts, avoids private network reachability requirements, and keeps private API posture while remaining repeatable and idempotent.
- Alternatives considered:
  - GitOps-only initial bootstrap: rejected as first step because controller bootstrap chain can be harder to diagnose in greenfield environments.
  - Manual private-network operator setup: rejected due to repeatability and dependency on human-operated private compute.
  - Separate workflow-driven bootstrap sequence: rejected as default due to split ownership and drift risk between infra and cluster bootstrap steps.

## Decision 9: Use `terraform_data` + `local-exec` for Terraform-invoked bootstrap scripts

- Decision: Implement ARC bootstrap invocation using Terraform built-in `terraform_data` resources with `provisioner "local-exec"`, explicit `depends_on`, and `triggers_replace` inputs (cluster identity + script content hash + bootstrap settings).
- Rationale: Current Terraform documentation explicitly supports `terraform_data` for arbitrary post-apply operations and trigger-driven re-execution without introducing an extra provider dependency. This is a more current and self-contained pattern than relying on `null_resource` for new implementations.
- Alternatives considered:
  - `null_resource` + `local-exec`: rejected as default for new work because `terraform_data` is the built-in recommended container for arbitrary operations.
  - External manual script execution after apply: rejected due to non-idempotent operator workflows and drift risk.
  - Pure provisioner-free bootstrap: rejected for this feature because ARC controller installation requires imperative post-cluster operations.
