# Remote Devcontainer Platform Scaffold

This repository bootstraps a platform for hosting remote development containers in Azure Kubernetes Service (AKS). The intended user flow is:

1. Developer signs into an enterprise VDI environment.
2. Developer uses VS Code from the VDI environment.
3. Developer connects to a remote dev container hosted in AKS.

The scaffold includes two core parts:

1. `devcontainer/`: image and runtime assets for a remote dev workspace (including VS Code server bootstrap). See the [Devcontainer Package README](devcontainer/README.md) for platform topology and connection options.
2. `ops/scripts/`: control-plane provisioning, deprovisioning, and federation/bootstrap scripts for platform operators.
3. `infra/`: demo topology implemented in Terraform with private networking and enterprise-oriented controls.

For step-by-step deployment and operations instructions, see the [Deployment Runbook](docs/DEPLOYMENT_RUNBOOK.md).

## Repository Layout

```text
.
|- devcontainer/
|  |- Dockerfile
|  |- manifests/
|  |- scripts/
|- ops/
|  |- scripts/
|- infra/
|  |- demo/
|- .specify/
|  |- templates/
|  |- memory/
|- .github/
|  |- ISSUE_TEMPLATE/
|  |- PULL_REQUEST_TEMPLATE.md
```

## Getting Started

After cloning, activate the repo's Git hooks (enforces commit message format and protects `main`/`master` client-side):

```bash
bash .githooks/setup-hooks.sh
```

When Terraform files under `infra/` are staged, the `pre-commit` hook runs:

- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`
- `tflint` (if installed)

## Notes

- This is a scaffold intended for iteration, not a production-ready deployment.
- The Terraform topology uses Azure Verified Modules (AVM) and defaults to private networking controls with disabled public endpoints where supported.
- The VS Code server startup script uses `code-server` as a practical bootstrap for remote browser/editor access patterns.
