# Remote Devcontainer Platform Scaffold

This repository bootstraps a platform for hosting remote development containers in Azure. The intended user flow is:

1. Developer signs into enterprise VDI.
2. Developer uses VS Code from the VDI environment.
3. Developer connects to a remote dev container hosted in AKS or Azure Container Apps.

The scaffold includes two core parts:

1. `devcontainer-package/`: image and runtime assets for a remote dev workspace (including VS Code server bootstrap).
2. `terraform/`: demo topology implemented in Terraform with private networking and enterprise-oriented controls.

It also includes a GitHub-native SpecKit-style feature workflow under `.github/` and `specs/`.

## Repository Layout

```text
.
|- devcontainer-package/
|  |- Dockerfile
|  |- manifests/
|  |- scripts/
|- terraform/
|  |- envs/demo/
|  |- modules/
|- specs/
|  |- templates/
|- .github/
|  |- ISSUE_TEMPLATE/
|  |- PULL_REQUEST_TEMPLATE.md
|- scripts/
```

## Quick Start

### 1) Build Devcontainer Image

```bash
cd devcontainer-package
docker build -t remote-devcontainer:latest .
```

### 2) Terraform Demo Topology

```bash
cd terraform/envs/demo
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan -out demo.tfplan
terraform apply -auto-approve demo.tfplan
```

Choose target platform(s) with `deploy_targets` in `terraform.tfvars`:

- `aks`
- `container_apps`
- both

### 3) Feature Management (SpecKit-style)

1. Create a feature proposal issue using the template in `.github/ISSUE_TEMPLATE/feature-proposal.yml`.
2. Generate a feature spec:

```bash
./scripts/new-feature-spec.sh <feature-slug>
```

3. Fill the spec template in `specs/features/<feature-slug>.md`.
4. Link the spec in your pull request using `.github/PULL_REQUEST_TEMPLATE.md`.

## Notes

- This is a scaffold intended for iteration, not a production-ready deployment.
- The Terraform topology defaults to private networking controls and disabled public endpoints where supported.
- The VS Code server startup script uses `code-server` as a practical bootstrap for remote browser/editor access patterns.
