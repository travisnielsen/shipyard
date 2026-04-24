# Tasks: Managed Egress via Azure Firewall

**Input**: Design documents from `/specs/003-managed-egress-firewall/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Tests were not explicitly requested in the specification; task list emphasizes Terraform validation and scenario verification steps.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- All tasks include exact file paths

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare Terraform inputs and operator documentation for the new egress mode model.

- [x] T001 Add baseline managed egress variable placeholders and comments in `infra/terraform.tfvars.example`
- [x] T002 [P] Add managed egress rollout notes and mode-selection section in `docs/DEPLOYMENT_RUNBOOK.md`
- [x] T003 [P] Add new output placeholders for active egress mode and managed egress resource identifiers in `infra/outputs.tf`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core validation and shared primitives required before any user story implementation.

**⚠️ CRITICAL**: No user story implementation should begin until this phase is complete.

- [x] T004 Add `managed_egress_enabled` and managed egress input variables with validation stubs in `infra/variables.tf`
- [x] T005 Implement mutual-exclusivity validation between `managed_egress_enabled` and `enable_nat_gateway` in `infra/variables.tf`
- [x] T006 Add CIDR overlap and required-input validation rules for managed egress hub network inputs in `infra/variables.tf`
- [x] T007 Add shared local values for effective egress mode and managed egress feature gating in `infra/locals.tf`
- [x] T008 Run Terraform static checks (`terraform fmt -check`, `terraform validate`) after foundational variable changes from `infra/`

**Checkpoint**: Foundation complete; user story implementation can begin.

---

## Phase 3: User Story 1 - Select Egress Mode Safely (Priority: P1) 🎯 MVP

**Goal**: Ensure exactly one outbound mode is active, with safe transitions that remove obsolete mode resources.

**Independent Test**: Toggle between managed mode and NAT mode in plan/apply workflows and verify only one mode is active with outbound continuity.

### Implementation for User Story 1

- [x] T009 [US1] Refactor NAT Gateway resources to be created only when effective mode is `nat_gateway` in `infra/networking.tf`
- [x] T010 [US1] Refactor NAT subnet associations (`aks_nodes`, `acr_tasks`, `vdi_integration`, `dev_vm`) to follow effective NAT mode in `infra/networking.tf`
- [x] T011 [US1] Add explicit mode-transition comments and safeguards for NAT removal/restore behavior in `infra/networking.tf`
- [x] T012 [US1] Add output `egress_mode_effective` and mode-specific output nullability rules in `infra/outputs.tf`
- [x] T013 [US1] Update operator examples for both valid mode combinations in `infra/terraform.tfvars.example`
- [x] T014 [US1] Add migration guidance (NAT -> managed and managed -> NAT) in `docs/DEPLOYMENT_RUNBOOK.md`
- [x] T015 [US1] Execute and record validation sequence for both mode combinations using commands in `specs/003-managed-egress-firewall/quickstart.md`

**Checkpoint**: User Story 1 delivers deterministic, mutually exclusive outbound mode behavior.

---

## Phase 4: User Story 2 - Apply Enterprise Hub-and-Spoke Pattern (Priority: P2)

**Goal**: Deploy Azure Firewall in a dedicated hub VNet peered to the Shipyard spoke VNet, and route outbound traffic through hub egress.

**Independent Test**: With managed egress enabled, verify hub VNet, bidirectional peering, route tables, and firewall-next-hop routing are present and effective.

### Implementation for User Story 2

- [x] T016 [US2] Add managed egress hub VNet and `AzureFirewallSubnet` resources in `infra/networking.tf`
- [x] T017 [US2] Add Azure Firewall public IP and firewall resource definitions in `infra/networking.tf`
- [x] T018 [US2] Add spoke-to-hub and hub-to-spoke VNet peering resources in `infra/networking.tf`
- [x] T019 [US2] Add managed egress route table(s) with default route `0.0.0.0/0` to firewall private IP in `infra/networking.tf`
- [x] T020 [P] [US2] Attach managed egress route table associations to outbound subnets (`aks_nodes`, `acr_tasks`, `vdi_integration`, `dev_vm`) in `infra/networking.tf`
- [x] T021 [US2] Update managed egress network outputs (hub VNet ID, firewall private IP, peering IDs) in `infra/outputs.tf`
- [x] T022 [US2] Extend deployment runbook with hub-and-spoke verification steps in `docs/DEPLOYMENT_RUNBOOK.md`
- [x] T023 [US2] Execute managed egress topology verification workflow and capture result notes in `specs/003-managed-egress-firewall/quickstart.md`

**Checkpoint**: User Story 2 establishes enterprise-aligned hub-and-spoke egress routing.

---

## Phase 5: User Story 3 - Enforce Domain-Based Outbound Controls (Priority: P3)

**Goal**: Apply deny-by-default outbound policy with DNS-name-based allow-list filtering and SKU-capability validation.

**Independent Test**: Verify allow-listed FQDNs succeed, non-allow-listed destinations are blocked, and invalid SKU/capability combinations fail validation.

### Implementation for User Story 3

- [x] T024 [US3] Add managed egress policy input variables for FQDN and IP allow-lists in `infra/variables.tf`
- [x] T025 [US3] Add duplicate/format validation for managed egress FQDN allow-list variables in `infra/variables.tf`
- [x] T026 [US3] Add firewall SKU variable validation and compatibility checks for policy capabilities in `infra/variables.tf`
- [x] T027 [US3] Add Azure Firewall Policy resource with default-deny posture in `infra/networking.tf`
- [x] T028 [US3] Add application rule collection resources for FQDN-based outbound allow-listing in `infra/networking.tf`
- [x] T029 [P] [US3] Add network rule collection resources for optional IP/CIDR allow-list entries in `infra/networking.tf`
- [x] T030 [US3] Associate firewall policy to Azure Firewall resource and ensure managed-mode-only gating in `infra/networking.tf`
- [x] T030a [US3] Add local value or variable default for platform-critical FQDN set (e.g., `var.managed_egress_required_platform_fqdns`) and implement policy generation logic to auto-merge these into effective allow-list with validation failure if omitted (satisfies FR-012)
- [ ] T031 [US3] Document policy authoring and required platform dependency FQDNs in `docs/DEPLOYMENT_RUNBOOK.md`
- [ ] T032 [US3] Execute outbound policy verification scenarios (allowed vs denied destinations) from `specs/003-managed-egress-firewall/quickstart.md`
- [ ] T032a [US3] Add Azure Firewall diagnostics settings resource with flow logs enabled and destination (e.g., Log Analytics workspace) in `infra/networking.tf` to satisfy FR-013
- [ ] T032b [US3] Add validation that Azure Firewall resource has diagnostic settings attached and logs for Application/Network rule denials are queryable via Kusto in `specs/003-managed-egress-firewall/quickstart.md`

**Checkpoint**: User Story 3 enforces DNS-capable allow-list outbound controls with validation guardrails and audit trail.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, safety checks, and end-to-end validation across stories.

- [ ] T033 [P] Align output descriptions and naming consistency across `infra/outputs.tf` and `infra/terraform.tfvars.example`
- [ ] T034 Perform final formatting and validation pass (`terraform fmt -check`, `terraform validate`) from `infra/`
- [ ] T035 Run end-to-end quickstart walkthrough and confirm documentation accuracy in `specs/003-managed-egress-firewall/quickstart.md`
- [ ] T036 [P] Update feature implementation notes and known limitations in `specs/003-managed-egress-firewall/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately
- **Foundational (Phase 2)**: Depends on Setup completion; blocks all user stories
- **User Story Phases (Phase 3-5)**: Depend on Foundational completion
- **Polish (Phase 6)**: Depends on completion of selected user stories

### User Story Dependencies

- **US1 (P1)**: Starts first after Foundational; defines mode exclusivity and transition baseline
- **US2 (P2)**: Depends on US1 mode gating to ensure NAT and managed egress resources do not conflict
- **US3 (P3)**: Depends on US2 firewall/policy-capable topology being in place

### Within Each User Story

- Variable/validation tasks before resource wiring
- Core resource deployment before outputs/docs
- Verification steps after implementation changes

### Parallel Opportunities

- T002 and T003 can run in parallel
- T020 can run in parallel with route-table construction finalization once route table exists
- T029 can run in parallel with T028 once policy scaffold exists
- T033 and T036 can run in parallel during polish

---

## Parallel Example: User Story 2

```bash
# After route table exists in T019, execute these in parallel:
Task: "Attach managed egress route table associations to outbound subnets in infra/networking.tf" (T020)
Task: "Update managed egress network outputs in infra/outputs.tf" (T021)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and Phase 2
2. Complete US1 (Phase 3)
3. Validate mode exclusivity and transition safety
4. Demo with NAT and managed mode plans

### Incremental Delivery

1. Deliver US1 for safe mode control and backward compatibility
2. Add US2 hub-and-spoke topology and routing
3. Add US3 outbound policy controls and DNS filtering
4. Perform final polish and end-to-end validation

### Parallel Team Strategy

1. Team aligns on foundational variable model and locals
2. Engineer A: US1 mode gating and NAT behavior
3. Engineer B: US2 network topology and routing
4. Engineer C: US3 policy and allow-list controls
5. Merge and execute final validation as a group

---

## Notes

- [P] tasks are scoped to independent files or independent resource blocks.
- Each user story remains independently testable after completion.
- Keep all networking and egress resource changes in `infra/networking.tf` per repo convention.
- Keep all new role assignments centralized in `infra/rbac.tf` only if role changes become necessary.
