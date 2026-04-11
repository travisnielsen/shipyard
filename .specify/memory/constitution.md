<!--
Sync Impact Report
Version: N/A → 1.0.0 (initial ratification)
Modified Principles: N/A (initial creation)
Added Sections:
  - Core Principles (6 principles)
  - Security Requirements
  - Automation Standards
  - Governance
Removed Sections: N/A
Templates:
  - .specify/templates/plan-template.md ✅ (Constitution Check gate already present)
  - .specify/templates/spec-template.md ✅ (no amendment required)
  - .specify/templates/tasks-template.md ✅ (no amendment required)
Deferred TODOs: None
-->

# Shipyard Constitution

## Core Principles

### I. Infrastructure-as-Code First

All infrastructure MUST be defined in code (Terraform or Bicep). Manual resource creation in shared or
production environments is forbidden. Every resource change MUST be traceable to a version-controlled
commit. Local experimentation in isolated subscriptions is permitted but MUST NOT be promoted to shared
environments without a corresponding IaC change.

### II. Private-by-Default Networking

All Azure resources MUST default to private endpoints with public network access disabled. Exceptions
require explicit justification in the feature specification and MUST be approved via PR review.
Default allow-all network policies are forbidden. DNS resolution for private endpoints MUST use Private
DNS Zones managed within the platform.

### III. Identity-Based Access

Workspace authentication MUST use Entra ID managed identities or user identity federation.
Password-based authentication (including `code-server --auth password` and `DEVCONTAINER_PASSWORD`) is
forbidden in all shared environments. Service-to-service access MUST use managed identities with RBAC
role assignments; connection strings and shared keys MUST NOT be used except where no managed identity
alternative exists (in which case credentials MUST be stored in Key Vault).

### IV. Immutable Workspaces

User workspace containers MUST be ephemeral and stateless. Container images MUST be rebuilt from source
on every provisioning cycle; in-place mutations to running containers are forbidden in shared
environments. All persistent state MUST reside in dedicated, externally mounted storage volumes.
Workspace deprovisioning MUST be fully scriptable and MUST NOT leave orphaned resources.

### V. Least-Privilege

All service principals, managed identities, and Entra group role assignments MUST follow the
least-privilege principle. Owner or Contributor role assignments at subscription scope are forbidden.
Role assignments MUST be scoped to the minimum required resource group or individual resource.
Privileged roles (e.g., Key Vault Administrator, AKS Cluster Admin) MUST be granted only to named
Entra groups, not to individual user accounts.

### VI. Simplicity

Prefer managed Azure services over self-hosted components when the security posture is equivalent or
better. Avoid custom automation where a first-party feature covers the requirement. New dependencies
(Helm charts, Terraform modules, scripts) MUST be justified by a concrete requirement; speculative or
convenience additions are forbidden.

## Security Requirements

- Secrets MUST be stored in Azure Key Vault. Hardcoded credentials in IaC, scripts, or container
  images are forbidden.
- Container images MUST be sourced from the platform's private Azure Container Registry. Public
  registry pulls in production workloads are forbidden.
- All CI/CD pipelines MUST use OIDC federated identity for Azure authentication. Long-lived service
  principal secrets stored as pipeline secrets are forbidden.
- Security guardrail scans (pattern-based checks for forbidden auth patterns and credential leakage)
  MUST pass on every pull request before merge.
- AKS node pools MUST enable Microsoft Defender for Containers and enforce pod security standards at
  the `restricted` profile unless a documented exception is approved.

## Automation Standards

- All provisioning and deprovisioning operations MUST be implemented as idempotent scripts
  (shell or PowerShell).
- CI/CD workflows MUST run `terraform validate` and `terraform plan` on every pull request that
  modifies `infra/`.
- Destructive operations (workspace teardown, infrastructure destroy) MUST require explicit
  confirmation flags and MUST NOT execute silently.
- Terraform modules MUST be pinned to exact versions. Floating version constraints are forbidden.
- Helm chart and Kubernetes manifest changes MUST pass `kubectl --dry-run=server` validation in CI.

## Governance

This constitution supersedes all other documented practices within the Shipyard repository. Conflicts
between this document and other guides MUST be resolved in favour of the constitution.

**Amendment procedure**: Amendments MUST be proposed via pull request with a description of the
change and rationale. Amendments that affect security principles or networking defaults MUST receive
at least one approving review from a platform maintainer before merge.

**Versioning policy**:
- MAJOR: Removal or backward-incompatible redefinition of an existing principle.
- MINOR: Addition of a new principle or section, or material expansion of existing guidance.
- PATCH: Clarifications, wording improvements, or non-semantic refinements.

**Compliance**: All feature implementation plans MUST complete the Constitution Check gate in
`plan-template.md` before proceeding to Phase 1. Violations discovered in review MUST be resolved
before merge.

**Review cadence**: The constitution SHOULD be reviewed at least once per quarter to reflect changes
in platform scope or Azure service capabilities.

**Version**: 1.0.0 | **Ratified**: 2026-04-11 | **Last Amended**: 2026-04-11
