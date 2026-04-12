# Tasks: AKS ARC GitHub Build Agents

**Input**: Design documents from `/specs/001-aks-arc-cd/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Test tasks are not included because the specification does not request test-first implementation. Validation tasks are included in each story phase.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create shared scaffolding and configuration files used by multiple stories

- [x] T001 Create operations script directory scaffold in ops/scripts/.gitkeep
- [x] T002 Create ARC bootstrap script scaffolds in ops/scripts/bootstrap-arc.sh and ops/scripts/bootstrap-arc.ps1
- [x] T003 [P] Add ARC bootstrap and runner pool input placeholders in infra/terraform.tfvars.example
- [x] T004 [P] Add feature runbook section stubs for ARC/bootstrap/nodepool flows in docs/DEPLOYMENT_RUNBOOK.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core platform and orchestration capabilities required before user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Add ARC bootstrap toggle, execution mode, and script invocation controls in infra/variables.tf
- [x] T006 Add dedicated runner node pool variables (size, min/max, labels, taints) in infra/variables.tf
- [x] T007 Add ARC and runner nodepool locals for naming/labels/taints in infra/locals.tf
- [x] T008 Implement dedicated runner node pool resource configuration in infra/main.tf
- [x] T009 Implement Terraform-orchestrated post-provision ARC bootstrap invocation using `terraform_data` + `local-exec` + `triggers_replace` in infra/main.tf
- [x] T010 Add ACR role assignment resources for ARC runtime identity (`AcrPull`/optional `AcrPush`) in infra/main.tf
- [x] T011 Add ARC bootstrap and runner nodepool outputs in infra/outputs.tf
- [x] T012 Document idempotent single-flow Terraform orchestration behavior and re-invocation triggers in specs/001-aks-arc-cd/quickstart.md

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Run Private GitHub Jobs on AKS (Priority: P1) 🎯 MVP

**Goal**: Deploy ARC and an autoscaling runner set so GitHub private jobs execute on AKS

**Independent Test**: Trigger a workflow targeting runner labels and verify pods start, execute, and recover from failure

### Implementation for User Story 1

- [x] T013 [US1] Add ARC controller install steps (Helm/kubectl commands via `az aks command invoke`) to ops/scripts/bootstrap-arc.sh
- [x] T014 [US1] Add ARC namespace and controller values file in infra/scripts/arc/controller-values.yaml
- [x] T015 [US1] Add autoscaling runner set manifest template in infra/scripts/arc/autoscaling-runner-set.yaml
- [x] T016 [US1] Add PowerShell command invocation parity and idempotency guards (`az aks command invoke`) in ops/scripts/bootstrap-arc.ps1
- [x] T017 [US1] Add runner scope/label/min-max parameters to bootstrap script in ops/scripts/bootstrap-arc.sh
- [x] T018 [US1] Add idempotency guards for ARC controller and runner set bootstrap in ops/scripts/bootstrap-arc.sh
- [x] T019 [US1] Add operational validation commands for ARC readiness in docs/DEPLOYMENT_RUNBOOK.md
- [x] T020 [US1] Add failure handling and retry guidance for ARC registration failures in docs/DEPLOYMENT_RUNBOOK.md

**Checkpoint**: User Story 1 is independently deployable and runnable

---

## Phase 4: User Story 2 - Configure Secure GitHub-to-Azure Federation (Priority: P2)

**Goal**: Provide idempotent federation setup so workflows authenticate to Azure without long-lived secrets

**Independent Test**: Run federation setup script and validate `azure/login` succeeds using emitted IDs

### Implementation for User Story 2

- [x] T021 [P] [US2] Implement PowerShell federation setup script in ops/scripts/setup-github-actions.ps1
- [x] T022 [P] [US2] Implement Bash federation setup script in ops/scripts/setup-github-actions.sh
- [x] T023 [US2] Add repository variable and subject-claim guidance in docs/DEPLOYMENT_RUNBOOK.md
- [x] T024 [US2] Add least-privilege RBAC mapping table for federation identity in docs/DEPLOYMENT_RUNBOOK.md
- [x] T025 [US2] Add Terraform local-exec runtime and auth prerequisites for bootstrap scripts in docs/DEPLOYMENT_RUNBOOK.md
- [x] T026 [US2] Add setup validation and remediation commands in specs/001-aks-arc-cd/quickstart.md

**Checkpoint**: User Story 2 is independently executable and secure

---

## Phase 5: User Story 5 - Place Build Agents on a Runner-Specific Node Pool (Priority: P2)

**Goal**: Ensure ARC runners schedule only to dedicated runner nodes with independent autoscaling (prefer min=0)

**Independent Test**: Run jobs and verify runner pods land on runner pool only; verify idle scale-down behavior

### Implementation for User Story 5

- [x] T027 [US5] Add runner nodepool labels and taints to infrastructure config in infra/main.tf
- [x] T028 [US5] Add runner pod nodeSelector and tolerations in infra/scripts/arc/autoscaling-runner-set.yaml
- [x] T029 [US5] Add runner pool autoscaling bounds and min=0 preference logic in infra/variables.tf
- [x] T030 [US5] Add fallback behavior when min=0 is unsupported in selected environment in infra/main.tf
- [x] T031 [US5] Add nodepool placement verification steps (`kubectl get pods -o wide`, label checks) in docs/DEPLOYMENT_RUNBOOK.md
- [x] T032 [US5] Add scale-to-minimum verification procedure in specs/001-aks-arc-cd/quickstart.md

**Checkpoint**: User Story 5 placement and scaling behavior are independently verifiable

---

## Phase 6: User Story 3 - Auto-Build Devcontainer Image on Change (Priority: P3)

**Goal**: Build and publish devcontainer image to ACR on `devcontainer/**` changes only

**Independent Test**: Change a file under `devcontainer/` and verify image is built/pushed; unrelated changes do not trigger

### Implementation for User Story 3

- [x] T033 [US3] Create workflow scaffold file and baseline job structure in .github/workflows/devcontainer-image-cd.yml
- [x] T034 [US3] Implement path-scoped workflow triggers in .github/workflows/devcontainer-image-cd.yml
- [x] T035 [US3] Add OIDC Azure login and ACR authentication steps in .github/workflows/devcontainer-image-cd.yml
- [x] T036 [US3] Add build and push steps from devcontainer context in .github/workflows/devcontainer-image-cd.yml
- [x] T037 [US3] Add image tagging strategy (`sha`, optional `branch-sha`) in .github/workflows/devcontainer-image-cd.yml
- [x] T038 [US3] Add workflow permissions, fail-closed behavior, and error messaging in .github/workflows/devcontainer-image-cd.yml
- [x] T039 [US3] Document CD workflow operation and troubleshooting in docs/DEPLOYMENT_RUNBOOK.md

**Checkpoint**: User Story 3 can be validated independently from ARC operations

---

## Phase 7: User Story 4 - Separate Control-Plane Scripts from Container Assets (Priority: P4)

**Goal**: Move lifecycle control-plane scripts to `ops/scripts` and keep `devcontainer/scripts` in-container only

**Independent Test**: Verify file relocation and all updated references resolve correctly

### Implementation for User Story 4

- [x] T040 [US4] Move provision script (PowerShell) to ops/scripts/provision-workspace.ps1 from devcontainer/scripts/provision-workspace.ps1
- [x] T041 [US4] Move provision script (Bash) to ops/scripts/provision-workspace.sh from devcontainer/scripts/provision-workspace.sh
- [x] T042 [US4] Move deprovision script (PowerShell) to ops/scripts/deprovision-workspace.ps1 from devcontainer/scripts/deprovision-workspace.ps1
- [x] T043 [US4] Move deprovision script (Bash) to ops/scripts/deprovision-workspace.sh from devcontainer/scripts/deprovision-workspace.sh
- [x] T044 [US4] Update script path references in docs/DEPLOYMENT_RUNBOOK.md
- [x] T045 [US4] Update script path references in devcontainer/README.md
- [x] T046 [US4] Update script path references in README.md

**Checkpoint**: User Story 4 completes repository structure cleanup without breaking operations

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, documentation, and operational readiness checks

- [x] T047 [P] Reconcile contracts with implementation outputs in specs/001-aks-arc-cd/contracts/arc-runner-contract.yaml
- [x] T048 [P] Reconcile bootstrap mode documentation with implementation defaults in specs/001-aks-arc-cd/contracts/arc-bootstrap-options-contract.yaml
- [x] T049 Validate full quickstart end-to-end and update findings in specs/001-aks-arc-cd/quickstart.md
- [x] T050 [P] Add final troubleshooting matrix for edge cases (including Terraform script invocation failures) in docs/DEPLOYMENT_RUNBOOK.md
- [x] T051 Update plan/status references to completed implementation artifacts in specs/001-aks-arc-cd/plan.md
- [x] T052 Add Stage 1 deployment section for Entra ID configuration (groups + GitHub federated credential) in docs/DEPLOYMENT_RUNBOOK.md
- [x] T053 Add Stage 2 deployment section for infrastructure provisioning (Terraform apply + Terraform-invoked ARC bootstrap) in docs/DEPLOYMENT_RUNBOOK.md
- [x] T054 Add Stage 3 deployment section for private-agent devcontainer image build/push trigger and verification in docs/DEPLOYMENT_RUNBOOK.md
- [x] T055 Validate the staged deployment guide (Stages 1-3) against implemented commands and expected outputs in docs/DEPLOYMENT_RUNBOOK.md
- [x] T056 Capture SC-001/SC-002/SC-007/SC-008/SC-009 validation evidence (run counts, timings, placement, scale-down outcomes) in specs/001-aks-arc-cd/quickstart.md
- [x] T057 Capture SC-003/SC-004/SC-005/SC-006 validation evidence (OIDC auth mode, build duration, setup duration, path integrity checks) in specs/001-aks-arc-cd/quickstart.md
- [x] T058 Produce final acceptance evidence matrix mapping FR-001..FR-018 and SC-001..SC-010 to collected proof artifacts in specs/001-aks-arc-cd/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story Phases**: Depend on Foundational completion
  - **US1 (Phase 3)** should be completed first as MVP
  - **US2 (Phase 4)** and **US5 (Phase 5)** are both P2 and can proceed in parallel after US1 baseline or directly after Foundational if staffed
  - **US3 (Phase 6)** depends on federation and ACR auth outputs from Foundational/US2
  - **US4 (Phase 7)** can proceed after Foundational and in parallel with US3 if script path conflicts are managed
- **Polish (Phase 8)**: Depends on all targeted user stories being complete

### User Story Dependencies

- **US1 (P1)**: Starts after Foundational; delivers MVP ARC capability
- **US2 (P2)**: Starts after Foundational; provides secure Azure auth needed by ARC/bootstrap/CD workflows
- **US5 (P2)**: Starts after Foundational; augments placement/scaling reliability for ARC runners
- **US3 (P3)**: Requires OIDC/Azure auth and ACR access from Foundational + US2
- **US4 (P4)**: Independent of ARC logic; depends on path update coordination across docs/workflows

### Within Each User Story

- Configuration/manifests before Terraform script invocation
- Terraform invocation wiring before operator documentation finalization
- RBAC/auth before image push or ARC runtime verification
- File moves before reference updates and validation

### Parallel Opportunities

- Setup tasks marked [P] can run in parallel
- In US2, script implementation tasks T021 and T022 can run in parallel
- In Polish, T047 and T048 can run in parallel
- US4 path ref updates can be split across docs once file moves complete

---

## Parallel Example: User Story 2

```bash
# Implement federation scripts in parallel:
Task: "Implement PowerShell federation setup script in ops/scripts/setup-github-actions.ps1"
Task: "Implement Bash federation setup script in ops/scripts/setup-github-actions.sh"
```

---

## Parallel Example: User Story 3

```bash
# After workflow scaffold exists, parallelize distinct edits:
Task: "Add OIDC Azure login and ACR authentication steps in .github/workflows/devcontainer-image-cd.yml"
Task: "Add image tagging strategy and fail-closed behavior in .github/workflows/devcontainer-image-cd.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: US1 (ARC deployment + runner execution)
4. Validate US1 independently before expanding scope

### Incremental Delivery

1. Deliver US1 for runnable private build agents
2. Add US2 for secure federation and OIDC hardening
3. Add US5 for deterministic nodepool placement and autoscaling behavior
4. Add US3 for devcontainer image CD automation
5. Add US4 for repository structure and maintainability cleanup

### Parallel Team Strategy

1. Team A: Infra/Terraform tasks (Foundational + US5)
2. Team B: ARC/bootstrap and federation scripts (US1 + US2)
3. Team C: Workflow and docs stream (US3 + US4 + Polish)

---

## Notes

- [P] tasks = different files, no direct dependency
- [US#] labels map tasks to user stories for traceability
- Story checkpoints are explicit stop points for independent validation
- Prefer small commits per task cluster (infra, scripts, workflows, docs)
- Keep ARC bootstrap idempotent to satisfy FR-018/SC-010 on re-run behavior
