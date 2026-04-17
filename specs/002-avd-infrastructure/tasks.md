# Tasks: Azure Virtual Desktop Infrastructure

**Input**: Design documents from `/specs/002-avd-infrastructure/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Test-first tasks are not included because the specification does not require TDD. Validation tasks are included in each user story phase.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create AVD implementation scaffolding and shared config touchpoints

- [x] T001 Create AVD infrastructure scaffold file in `infra/avd.tf`
- [x] T002 Create AVD variable definitions scaffold in `infra/avd_variables.tf`
- [x] T003 [P] Add AVD example input placeholders (`deploy_avd`, `avd_users_entra_group_id`, `avd_session_host_count`, `avd_session_host_sku`) in `infra/terraform.tfvars.example`
- [x] T004 [P] Add AVD deployment section stub in `infra/README.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core platform prerequisites that MUST be complete before any user story implementation

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Bump Terraform minimum version to `>= 1.10.0` and add `tls ~> 4.0` provider in `infra/versions.tf`
- [x] T006 Implement validation-backed AVD input variables in `infra/avd_variables.tf`
- [x] T007 Update `vdi_integration` subnet NAT gateway association to link the existing workload NAT gateway (conditional on `enable_nat_gateway`) in `infra/main.tf`
- [x] T008 Add shared AVD naming locals and feature-flag wiring in `infra/avd.tf`
- [x] T009 Add dedicated AVD Key Vault resource for generated session host credentials in `infra/avd.tf`
- [x] T010 Add foundational AVD outputs scaffold (`avd_workspace_url`, `avd_keyvault_name`) in `infra/outputs.tf`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Access a Windows 11 Desktop via AVD (Priority: P1) 🎯 MVP

**Goal**: Allow authorized same-tenant Entra ID users to sign in and reach a Windows 11 AVD desktop

**Independent Test**: Assign test user to Entra ID group, sign in through AVD client, verify desktop connection succeeds; verify non-assigned user is denied

### Implementation for User Story 1

- [x] T011 [US1] Implement AVM host pool module (`Pooled`, `BreadthFirst`, max sessions, start VM on connect) in `infra/avd.tf`
- [x] T012 [US1] Implement AVM desktop application group module and group-scoped `Desktop Virtualization User` RBAC assignment in `infra/avd.tf`
- [x] T013 [US1] Implement AVM workspace module and app group association resource in `infra/avd.tf`
- [x] T014 [US1] Implement session host VM module in `infra/avd.tf` using `win11-25h2-avd`, `Standard_D2s_v5`, and `vdi_integration` subnet placement
- [x] T015 [US1] Add `AADLoginForWindows` extension configuration for Entra ID join in `infra/avd.tf`
- [x] T016 [US1] Wire host pool registration token dependency for session host registration flow in `infra/avd.tf`
- [x] T017 [US1] Add user sign-in and unauthorized-access validation steps in `specs/002-avd-infrastructure/quickstart.md`

**Checkpoint**: User Story 1 is independently deployable and testable

---

## Phase 4: User Story 2 - Use VS Code and Azure CLI from the Desktop (Priority: P2)

**Goal**: Ensure VS Code and Azure CLI are preinstalled and available immediately in each desktop session

**Independent Test**: Connect to desktop, launch VS Code, run `az --version`, reboot session host, reconnect, verify both tools remain available

### Implementation for User Story 2

- [x] T018 [US2] Add Custom Script Extension shell in `infra/avd.tf` for post-provision tool installation
- [x] T019 [US2] Implement VS Code silent install commands in Custom Script Extension payload in `infra/avd.tf`
- [x] T020 [US2] Implement Azure CLI MSI install commands in Custom Script Extension payload in `infra/avd.tf`
- [x] T021 [US2] Add AVD RDAgent and boot loader install commands with protected registration token handling in `infra/avd.tf`
- [x] T022 [P] [US2] Add tool verification and post-restart validation steps in `specs/002-avd-infrastructure/quickstart.md`
- [x] T023 [P] [US2] Add troubleshooting guidance for extension/tool-install failures in `specs/002-avd-infrastructure/quickstart.md`

**Checkpoint**: User Story 2 is independently verifiable on top of US1 deployment

---

## Phase 5: User Story 3 - Provision and Manage AVD Infrastructure via Terraform (Priority: P3)

**Goal**: Manage full AVD lifecycle with Terraform, including idempotent apply and safe `deploy_avd=false` teardown

**Independent Test**: Run `terraform apply` from zero, verify resources created; run `terraform plan` for idempotency; set `deploy_avd=false` and verify only AVD resources are removed

### Implementation for User Story 3

- [x] T024 [US3] Gate all AVD resources behind `deploy_avd` feature flag in `infra/avd.tf`
- [x] T025 [US3] Add required AVD outputs (`avd_workspace_url`, `avd_keyvault_name`) in `infra/outputs.tf`
- [x] T026 [US3] Reconcile variable contract documentation with implemented validation behavior in `specs/002-avd-infrastructure/contracts/avd-terraform-variables-contract.yaml`
- [x] T027 [US3] Add AVD deployment/teardown and idempotency verification flow in `specs/002-avd-infrastructure/quickstart.md`
- [x] T028 [US3] Align contract text with final variable behavior in `specs/002-avd-infrastructure/contracts/avd-terraform-variables-contract.yaml`

**Checkpoint**: User Story 3 provides reproducible full lifecycle management via Terraform

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, validation, and documentation hardening across stories

- [x] T029 [P] Run Terraform formatting and validation for AVD changes (`fmt`, `validate`, `plan`) and apply required fixes in `infra/avd.tf`
- [x] T030 [P] Update AVD implementation details and outputs in `infra/README.md`
- [x] T031 Add AVD deployment and operations runbook section in `docs/DEPLOYMENT_RUNBOOK.md`
- [ ] T032 Validate quickstart end-to-end against implemented code and capture final evidence in `specs/002-avd-infrastructure/quickstart.md`
- [x] T033 [P] Implement and verify `var.tags` propagation on all AVD resources (host pool, app group, workspace, VM, Key Vault) in `infra/avd.tf`
- [ ] T034 Measure and record SC-001 connect latency (<3 minutes) with test evidence in `specs/002-avd-infrastructure/quickstart.md`
- [ ] T035 Verify SC-006 network posture (no public IP, no inbound exposure, Bastion/admin path only) and record evidence in `specs/002-avd-infrastructure/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-5)**: Depend on Foundational completion
  - **US1 (Phase 3)** should be completed first as MVP
  - **US2 (Phase 4)** depends on session host provisioning from US1
  - **US3 (Phase 5)** can begin after Foundational and run in parallel with US2, but final lifecycle validation depends on US1 resources
- **Polish (Phase 6)**: Depends on all targeted user stories being complete

### User Story Dependencies

- **US1 (P1)**: Starts after Foundational; delivers core desktop sign-in capability
- **US2 (P2)**: Starts after US1 session host baseline exists
- **US3 (P3)**: Starts after Foundational; validates lifecycle behavior across US1/US2 infrastructure

### Within Each User Story

- AVM control-plane resources before VM extension-dependent steps
- VM base configuration before Entra join extension
- Entra join and registration before user sign-in validation
- Tool installation payload before quickstart verification/troubleshooting updates
- Output and contract updates before lifecycle validation sign-off

### Parallel Opportunities

- Setup tasks marked `[P]` can run in parallel
- In US2, quickstart verification and troubleshooting updates can run in parallel (T022, T023)
- In Polish, Terraform validation and README updates can run in parallel (T029, T030)

---

## Parallel Example: User Story 1

```bash
# Parallelize independent control-plane resources after host pool interface is defined:
Task: "Implement AVM desktop application group module and RBAC assignment in infra/avd.tf"
Task: "Implement AVM workspace module and app group association resource in infra/avd.tf"
```

---

## Parallel Example: User Story 2

```bash
# Parallelize documentation updates after extension payload is implemented:
Task: "Add tool verification and post-restart validation steps in specs/002-avd-infrastructure/quickstart.md"
Task: "Add troubleshooting guidance for extension/tool-install failures in specs/002-avd-infrastructure/quickstart.md"
```

---

## Parallel Example: User Story 3

```bash
# Parallelize implementation vs documentation alignment:
Task: "Add required AVD outputs in infra/outputs.tf"
Task: "Align contract text with final variable behavior in specs/002-avd-infrastructure/contracts/avd-terraform-variables-contract.yaml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: US1
4. Validate US1 independently (authorized sign-in, unauthorized deny)
5. Demo MVP

### Incremental Delivery

1. Deliver US1 (desktop access)
2. Add US2 (VS Code + Azure CLI readiness)
3. Add US3 (full Terraform lifecycle and teardown control)
4. Finish with Polish validation and runbook updates

### Parallel Team Strategy

1. Engineer A: Terraform platform prerequisites (Phases 1-2)
2. Engineer B: AVD control plane and session host onboarding (US1)
3. Engineer C: Tooling extension and operator docs (US2 + US3 docs)

---

## Notes

- `[P]` tasks indicate file-level independence and no blocking dependency on incomplete tasks
- `[US#]` labels map each task to one user story for clear traceability
- Each user story has an independent test criterion and checkpoint
- Keep commits scoped by task group (foundation, US1, US2, US3, polish)
