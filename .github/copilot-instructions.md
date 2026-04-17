# shipyard Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-16

## Active Technologies
- HCL / Terraform >= 1.10.0 (bumped from 1.9 — required by `avm-res-compute-virtualmachine` v0.20.0) (002-avd-infrastructure)
- N/A (no application data storage; admin credentials in Azure Key Vault) (002-avd-infrastructure)

- Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values + Azure CLI (`az`), `kubectl`, `helm`, GitHub Actions (`azure/login`), ARC Helm charts (001-add-aks-arc-cd)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values

## Code Style

Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values: Follow standard conventions

## Recent Changes
- 002-avd-infrastructure: Added HCL / Terraform >= 1.10.0 (bumped from 1.9 — required by `avm-res-compute-virtualmachine` v0.20.0)

- 001-add-aks-arc-cd: Added Terraform >=1.9, YAML (GitHub Actions), Bash, PowerShell 7, Kubernetes manifests/Helm values + Azure CLI (`az`), `kubectl`, `helm`, GitHub Actions (`azure/login`), ARC Helm charts

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
