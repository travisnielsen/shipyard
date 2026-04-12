# Implementation Plan: AKS ARC GitHub Build Agents

**Branch**: `001-add-aks-arc-cd` | **Date**: 2026-04-11 | **Spec**: `/specs/001-aks-arc-cd/spec.md`
**Input**: Feature specification from `/specs/001-aks-arc-cd/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Add private GitHub build agents to the existing Shipyard AKS deployment using Actions Runner Controller,
establish Entra ID OIDC federation for GitHub Actions with idempotent setup scripts, create a path-scoped
devcontainer image CD workflow to publish to Shipyard ACR, and reorganize workspace control-plane scripts
into a new top-level `ops/scripts` directory. ARC bootstrap is executed via control-plane or in-cluster
automation paths that avoid dedicated jump-host infrastructure. Runner workloads are hosted on a dedicated,
explicitly selected AKS user node pool with independent autoscaling (prefer min `0` where supported). The
default operator path runs provisioning and ARC bootstrap in a single Terraform-driven deployment flow.

## Technical Context

**Language/Version**: Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values  
**Primary Dependencies**: Azure CLI (`az`), `kubectl`, `helm`, GitHub Actions (`azure/login`), ARC Helm charts  
**Storage**: Azure Container Registry for devcontainer images; existing Azure Storage for workspace volumes  
**Testing**: `terraform validate`, `terraform plan`, hook-enforced `terraform fmt -check`, runner registration smoke workflow, ARC identity ACR pull/push authorization validation, nodepool placement verification (`kubectl get pod -o wide` + label checks), idle scale-down verification, image build workflow run validation  
**Target Platform**: Azure (AKS, ACR, Entra ID), GitHub Actions, Linux-based runner pods
**Project Type**: Infrastructure-as-code + DevOps automation repository  
**Performance Goals**: ARC jobs start within 2 minutes in >=95% validation runs; devcontainer image publish under 10 minutes in >=90% runs  
**Constraints**: Private-by-default networking, OIDC-only Azure auth from GitHub Actions, least-privilege RBAC, no long-lived app secrets, no dedicated jump-host dependency for ARC bootstrap, idempotent single-flow provisioning + bootstrap  
**Scale/Scope**: Initial onboarding for one repository, one primary runner set, and one dedicated runner node pool with independent autoscaling bounds

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Gate 1 - IaC first**: PASS. All changes are repo-managed infra/workflow/script updates.
- **Gate 2 - Private-by-default networking**: PASS. No public endpoint requirement introduced; ARC runs in existing private AKS.
- **Gate 3 - Identity-based access**: PASS. Plan requires Entra OIDC federation and forbids long-lived secrets.
- **Gate 4 - Immutable workspaces**: PASS. Devcontainer image automation supports rebuild-from-source behavior.
- **Gate 5 - Least-privilege**: PASS. Federation and ARC contracts require scoped RBAC; ACR access is explicitly constrained to `AcrPull` minimum and `AcrPush` only when publish behavior is required.
- **Gate 6 - Simplicity**: PASS. Uses standard ARC and GitHub OIDC patterns; avoids bespoke auth systems.

Post-Phase-1 Re-check: PASS. `research.md`, `data-model.md`, `quickstart.md`, and `contracts/*` remain compliant with all constitution gates.

## Project Structure

### Documentation (this feature)

```text
specs/001-aks-arc-cd/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── arc-runner-contract.yaml
│   ├── arc-bootstrap-options-contract.yaml
│   ├── github-federation-script-contract.yaml
│   └── devcontainer-cd-workflow-contract.yaml
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
.github/
├── workflows/
│   ├── terraform-ci.yml.example
│   ├── security-guardrails.yml.example
│   └── devcontainer-image-cd.yml            # new

infra/
└── demo/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  └── scripts/

devcontainer/
├── Dockerfile
├── manifests/
└── scripts/
  ├── start-vscode-server.sh               # remains
  └── healthcheck.sh                       # remains

ops/                                         # new
└── scripts/
  ├── provision-workspace.ps1              # moved from devcontainer/scripts
  ├── provision-workspace.sh               # moved from devcontainer/scripts
  ├── deprovision-workspace.ps1            # moved from devcontainer/scripts
  ├── deprovision-workspace.sh             # moved from devcontainer/scripts
  ├── setup-github-actions.ps1             # new
  └── setup-github-actions.sh              # new

docs/
└── DEPLOYMENT_RUNBOOK.md
```

**Structure Decision**: Use the existing infra/devcontainer/docs repository structure with two additions: (1) `ops/scripts` as the control-plane automation boundary and (2) a dedicated devcontainer image CD workflow under `.github/workflows`.

## Phase 0 Research Output

- `research.md` documents bootstrap option tradeoffs and selected fallback order.
- Default ARC bootstrap: Terraform-orchestrated post-provision execution of `ops/scripts/bootstrap-arc.*` that run Azure control-plane commands (`az aks command invoke`) in the same deployment pipeline.
- Secondary bootstrap mode: GitOps reconciliation from in-cluster controller.
- Dedicated runner nodepool required for deterministic runner scheduling and scale behavior.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations identified.

## Implementation Status

- Completed: Setup, Foundational, and US1 tasks (T001-T020)
- Completed: US2 federation scripts/docs (T021-T026)
- Completed: US5 runner nodepool placement and scaling fallback/docs (T027-T032)
- Completed: US3 devcontainer path-scoped CD workflow and runbook updates (T033-T039)
- Completed: US4 control-plane script relocation and reference updates (T040-T046)
- Completed: Polish pass updates for contracts, quickstart evidence templates, staged deployment guide, and troubleshooting matrix (T047-T058)
