# Feature Specification: AKS ARC GitHub Build Agents

**Feature Branch**: `001-add-aks-arc-cd`  
**Created**: 2026-04-11  
**Status**: Draft  
**Input**: User description: "Create a new feature that adds GitHub private build agents to the AKS cluster already defined in Shipyard using Actions Runner Controller, including scripts and documentation for Entra ID federation with the GitHub repo, and a continuous deployment workflow watching `devcontainer` changes to build container images for the deployed ACR instance."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run Private GitHub Jobs on AKS (Priority: P1)

As a platform maintainer, I can provision and operate private GitHub build agents in the existing AKS cluster so repository workflows can run on controlled infrastructure.

**Why this priority**: This is the core platform capability and the primary reason for the feature.

**Independent Test**: Can be fully tested by registering runners, dispatching a test workflow targeting the private runner label, and confirming job execution completes on AKS-hosted agents.

**Acceptance Scenarios**:

1. **Given** ARC is deployed to the existing AKS cluster, **When** a GitHub workflow targets the private runner group/label, **Then** an AKS runner pod is created and executes the job successfully.
2. **Given** no queued GitHub jobs, **When** the runner system is idle, **Then** runner capacity scales back to the configured minimum.
3. **Given** a failed runner pod, **When** ARC reconciles desired state, **Then** replacement runner capacity is restored without manual intervention.

---

### User Story 2 - Configure Secure GitHub-to-Azure Federation (Priority: P2)

As a platform maintainer, I can run setup scripts and follow clear documentation to configure Entra ID federation for this repository so GitHub workflows access Azure without stored long-lived secrets.

**Why this priority**: Secure identity setup is required for safe automation and aligns with the project constitution.

**Independent Test**: Can be fully tested by running the federation setup scripts, executing a workflow that requests Azure tokens, and confirming Azure operations succeed without client secrets.

**Acceptance Scenarios**:

1. **Given** the required tenant/subscription and repository inputs, **When** the federation setup script is executed, **Then** required identity artifacts and role assignments are created and output for verification.
2. **Given** federation setup is complete, **When** the repository workflow authenticates to Azure, **Then** authentication succeeds via federated identity and no static secret is required.
3. **Given** setup prerequisites are missing, **When** setup is executed, **Then** the script exits with actionable validation errors.

---

### User Story 3 - Auto-Build Devcontainer Image on Change (Priority: P3)

As a platform maintainer, I can rely on a continuous deployment workflow that watches `devcontainer` directory changes and automatically builds/publishes the container image to the deployment's ACR.

**Why this priority**: It keeps workspace images current and reduces manual operational work.

**Independent Test**: Can be fully tested by changing a file under `devcontainer`, pushing the branch, and verifying the image build and registry publish complete successfully.

**Acceptance Scenarios**:

1. **Given** a commit modifies files under `devcontainer`, **When** the workflow runs, **Then** the container image is built and pushed to the configured ACR repository.
2. **Given** a commit does not modify `devcontainer`, **When** workflows run, **Then** the container image build workflow does not trigger.
3. **Given** registry push permissions are missing, **When** workflow execution reaches publish, **Then** the job fails with a clear authorization error.

---

### User Story 4 - Separate Control-Plane Scripts from Container Assets (Priority: P4)

As a platform maintainer, all workspace lifecycle scripts (provisioning, deprovisioning) are located in a dedicated top-level directory so the repository layout clearly separates platform operations tooling from the container image build assets.

**Why this priority**: Reduces confusion for contributors and coding agents, and ensures the `devcontainer` directory contains only what is baked into or executes inside the workspace container.

**Independent Test**: Can be fully tested by verifying the repository layout — provisioning/deprovisioning scripts are absent from `devcontainer/scripts` and present under the new `ops/scripts` directory, all documentation and workflow references are updated, and existing functionality is unaffected.

**Acceptance Scenarios**:

1. **Given** the current repository layout, **When** the reorganisation is applied, **Then** `provision-workspace.ps1`, `provision-workspace.sh`, `deprovision-workspace.ps1`, and `deprovision-workspace.sh` exist under `ops/scripts/` and are absent from `devcontainer/scripts/`.
2. **Given** the reorganised layout, **When** a maintainer navigates `devcontainer/scripts/`, **Then** only scripts that execute inside the container (`start-vscode-server.sh`, `healthcheck.sh`) remain there.
3. **Given** updated references, **When** all documentation and workflow files are reviewed, **Then** no broken paths referring to the old script locations exist.

---

### User Story 5 - Place Build Agents on a Runner-Specific Node Pool (Priority: P2)

As a platform maintainer, ARC runner pods are scheduled onto an explicitly defined runner node pool so build workloads do not contend with workspace or system workloads and are reliably schedulable.

**Why this priority**: Correct runner placement is required for reliability and predictable scaling, and prevents node taint/selector mismatches from blocking builds.

**Independent Test**: Can be fully tested by triggering runner jobs, validating runner pods land on the intended node pool via labels/taints/tolerations, and confirming scale behavior meets configuration.

**Acceptance Scenarios**:

1. **Given** runner node pool configuration is applied, **When** ARC creates runner pods, **Then** runner pods schedule only on nodes labeled for runner workloads.
2. **Given** runner node pool taints are configured, **When** non-runner workloads are scheduled, **Then** they are not placed on runner nodes unless explicitly tolerated.
3. **Given** no queued runner jobs, **When** autoscaling reconciles capacity, **Then** runner node pool capacity scales down to the configured minimum (preferably `0` where supported).

---

### Edge Cases

- What happens when GitHub API rate limits or transient outages delay runner registration and scale events?
- How does the system behave when AKS has insufficient capacity to schedule new runner pods?
- What happens when federation exists but repository/environment subject claims do not match expected trust configuration?
- How does the workflow behave if the ACR instance exists but denies push due to missing role assignment?
- What happens when multiple commits to `devcontainer` occur in quick succession and overlapping build runs are triggered?
- What happens if the `ops/scripts` location is not updated in all documentation references, leading to broken operator procedures?
- What happens if ARC runner pod node selectors/tolerations do not match available node pool labels/taints?
- What happens if the target Azure region/SKU combination does not support scaling the runner node pool minimum to `0`?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy and configure Actions Runner Controller in the existing AKS cluster managed by this repository.
- **FR-002**: System MUST provision at least one autoscaling private runner set that can execute GitHub Actions jobs from the target repository.
- **FR-003**: System MUST allow maintainers to configure runner scope (repository or organization) and runner labels through repository-managed configuration.
- **FR-004**: System MUST include automation scripts to set up Entra ID workload identity federation for GitHub Actions in this repository.
- **FR-005**: System MUST provide setup documentation that includes prerequisites, execution steps, expected outputs, validation checks, and rollback/remediation guidance for federation setup.
- **FR-006**: System MUST configure GitHub workflow authentication to Azure using federated identity rather than long-lived client secrets.
- **FR-007**: System MUST include a CI/CD workflow that triggers on changes under `devcontainer/**` and builds/publishes the workspace image to the ACR associated with this deployment.
- **FR-008**: System MUST prevent unnecessary image builds by scoping workflow triggers to `devcontainer/**` path changes.
- **FR-009**: System MUST provide clear operator-facing failure messages for common authentication, authorization, and runner registration failures.
- **FR-010**: System MUST document operational run procedures for validating runner health, federation status, and latest image publish status.
- **FR-011**: Control-plane workspace lifecycle scripts (provision, deprovision) MUST be relocated from `devcontainer/scripts/` to a new top-level `ops/scripts/` directory. Only scripts that execute inside the container MAY remain in `devcontainer/scripts/`. All documentation and workflow references MUST be updated to reflect the new paths.
- **FR-012**: GitHub ARC bootstrapping for the private AKS cluster MUST be executable through Terraform-managed configuration and automation steps that do not require a dedicated jump server or other always-on private compute solely for bootstrap operations.
- **FR-018**: The default deployment path MUST orchestrate AKS infrastructure provisioning and ARC controller bootstrap as a single Terraform-driven process (with post-provision invocation in the same run pipeline). Re-runs MUST be idempotent and MUST NOT duplicate ARC installation artifacts.
- **FR-013**: The ARC runtime identity MUST receive required Azure Container Registry permissions for this deployment: `AcrPull` at minimum for image retrieval, and `AcrPush` when runner workloads are configured to publish images. Role assignments MUST be least-privilege and scoped to the target registry or resource group.
- **FR-014**: ARC runner workloads MUST be scheduled using explicit node placement controls (`nodeSelector`/affinity and tolerations) that target a runner-designated AKS user node pool.
- **FR-015**: The platform MUST support a dedicated AKS runner node pool for GitHub ARC workloads, with labels and taints distinct from workspace node pools.
- **FR-016**: Runner node pool autoscaling MUST be configurable independently from workspace pools. Minimum capacity SHOULD be `0` when supported by platform constraints. Support for `0` MUST be determined by Terraform preflight validation against the selected region, AKS cluster mode, and node pool VM SKU/API constraints for user pools. If `0` is not supported in the selected environment, the minimum MUST default to the lowest supported value and be documented.
- **FR-017**: Documentation and validation procedures MUST include checks confirming runner pod placement on the intended node pool and verifying scale-down behavior.

### Key Entities *(include if feature involves data)*

- **Runner Set Configuration**: Defines runner scope, labels, scaling bounds, and execution characteristics used to schedule private GitHub jobs in AKS.
- **Federated Identity Configuration**: Defines trust relationship between GitHub repository/workflow subjects and Entra ID token issuance used for Azure access.
- **Registry Build Workflow Definition**: Defines trigger paths, build context, target image naming, and publish destination for the devcontainer image.
- **Operational Validation Record**: Captures post-setup checks (runner online state, federation auth success, and latest image digest publication).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of test workflows targeting the private runner label complete on AKS-hosted runners in validation runs.
- **SC-002**: New queued runner jobs begin execution within 2 minutes in at least 95% of validation runs.
- **SC-003**: 100% of successful Azure-authenticated workflow runs use federated identity with no long-lived Azure client secret configured in repository secrets.
- **SC-004**: A commit that changes files under `devcontainer/**` results in a published image artifact in the target registry in under 10 minutes in at least 90% of runs.
- **SC-005**: Maintainers can complete initial federation setup using documented steps and scripts in under 30 minutes without out-of-band instructions.
- **SC-006**: After reorganisation, 100% of documentation and workflow file references resolve correctly to the new script locations with no broken paths.
- **SC-007**: In validation runs, ARC runner jobs that require image pull succeed 100% of the time with configured `AcrPull`, and image publish jobs succeed when `AcrPush` is enabled for the ARC identity.
- **SC-008**: In validation runs, 100% of ARC runner pods are scheduled on the runner-designated node pool (and not on system/workspace pools unless explicitly intended).
- **SC-009**: Runner node pool scales down to configured minimum after idle periods in at least 95% of validation runs; where minimum is `0`, idle scale reaches zero nodes.
- **SC-010**: In a greenfield deployment, a single Terraform-driven execution completes AKS provisioning and ARC bootstrap successfully without manual intermediate steps.

## Assumptions

- The existing AKS cluster and ACR resources defined in this repository remain the deployment targets for this feature.
- Repository maintainers have permissions to create or update Entra ID app registrations/federated credentials and assign required Azure RBAC roles.
- GitHub repository settings allow adding required workflow permissions and environments for federated authentication.
- Private network routing and DNS required for AKS-to-ACR communication are already established by the current infrastructure stack.
- This feature scope covers one primary repository onboarding path first; multi-repo rollout patterns can be added later.
- The `ops/scripts/` directory contains control-plane and identity helpers (including `create-workspace-group.ps1`) for operator-driven setup flows.
- Bootstrap operations for private AKS integration can be executed via Azure control-plane or in-cluster GitOps patterns, without introducing long-lived jump-host infrastructure.
- A dedicated runner node pool can be added to the existing AKS cluster without changing the private networking topology.
