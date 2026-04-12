# Day-2 Operations

This document covers post-deployment and ongoing operating procedures for Shipyard after the shared infrastructure has already been provisioned.

## 1. ARC Bootstrap (Terraform-Orchestrated)

Run ARC bootstrap through Terraform by enabling `arc_bootstrap_enabled = true` in `infra/terraform.tfvars`.

Stub topics to complete during implementation:

- Verify `arc_bootstrap_execution_mode` and `arc_bootstrap_script_shell` values.
- Set `arc_bootstrap_config_url`, `arc_bootstrap_runner_scope`, and runner replica bounds.
- Confirm script execution host has `az` and `kubectl` prerequisites when using bootstrap scripts.

Operational validation commands:

```bash
az aks command invoke \
  --resource-group "<resource-group>" \
  --name "<aks-cluster-name>" \
  --command "kubectl get pods -n arc-systems; kubectl get pods -n arc-runners; kubectl get autoscalingrunnersets -n arc-runners"
```

Expected signals:

- ARC controller pod in `arc-systems` reaches `Running` and `Ready`.
- `AutoscalingRunnerSet` exists in `arc-runners` and reports reconciled state.
- Runner jobs scheduled from GitHub create transient runner pods in `arc-runners`.

Failure handling and retry guidance:

- If `az aks command invoke` fails with auth/subscription errors:
  - Re-run `az login` and confirm `az account show` points to the target subscription.
  - Re-run Terraform apply after fixing auth context.
- If Helm install/upgrade fails:
  - Re-run bootstrap by applying Terraform again after correcting chart/version inputs.
  - Validate cluster outbound connectivity and DNS from the AKS control-plane execution path.
- If runner set remains unscheduled:
  - Validate runner node pool labels and taints match ARC template selector/toleration values.
  - Validate node pool min/max bounds and available cluster capacity.

## 1.1 Dedicated Runner Nodepool Validation

The dedicated runner nodepool is created as part of the Section 4 Terraform deployment from the deployment runbook. This section is post-apply validation only.

Validation steps:

- Confirm runner pool outputs:
  - `terraform output arc_runner_nodepool_name`
  - `terraform output arc_runner_nodepool_effective_min_count`
- If `arc_runner_nodepool_min_count = 0` and scale-to-zero is unsupported in the chosen environment, set `arc_runner_nodepool_scale_to_zero_supported = false`; Terraform will automatically use effective minimum `1`.

Placement verification commands:

```bash
az aks command invoke --resource-group "<resource-group>" --name "<aks-cluster-name>" --command "kubectl get nodes -L kubernetes.azure.com/agentpool,workload"
az aks command invoke --resource-group "<resource-group>" --name "<aks-cluster-name>" --command "kubectl get pods -n arc-runners -o wide"
```

## 2. Day-2 Operations

### 2.1 Update Workspace Image

1. Trigger `.github/workflows/devcontainer-image-cd.yml` with a change under `devcontainer/`.
2. Re-run user provisioning script to roll updates.

### 2.2 Devcontainer CD Workflow (GitHub Actions)

Workflow file: `.github/workflows/devcontainer-image-cd.yml`

Behavior summary:

- Triggers only on `devcontainer/**` path changes
- Runs on the private ARC runner label set: `self-hosted`, `linux`, `shipyard-private`, `aks`
- Uses OIDC (`azure/login`) for Azure auth
- Builds and pushes image tags:
  - required: `${GITHUB_SHA}`
  - optional branch-sha: `${branch}-${GITHUB_SHA}`

Failure handling:

- Missing `AZURE_*` or `ACR_LOGIN_SERVER` repository variables fails job immediately.
- ACR auth/push failures fail closed with non-zero exit and job summary context.
