# Quickstart: AKS ARC GitHub Build Agents

## Prerequisites

- Existing Shipyard deployment from `infra/demo` with AKS and ACR.
- `kubectl`, `helm`, `az`, and `terraform` installed.
- GitHub repository admin permissions for Actions and variables/secrets.
- Azure permissions to create app registrations, federated credentials, and scoped role assignments.

## 1. Prepare repository and hooks

```bash
bash .githooks/setup-hooks.sh
```

## 2. Configure Entra federation for GitHub Actions

- Run the setup script under `ops/scripts/` with subscription/repo inputs.
- Capture emitted values: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ARC_RUNTIME_PRINCIPAL_ID`.
- Add these as GitHub Actions repository variables.
- Set `arc_runtime_principal_id` in `infra/demo/terraform.tfvars` to the emitted `ARC_RUNTIME_PRINCIPAL_ID` when using the same principal for GitHub federation and ARC runtime ACR RBAC.
- Verify with a test workflow step:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

Validation and remediation:

- Validate OIDC auth: run `az account show` in workflow after `azure/login`.
- If auth fails, re-run `ops/scripts/setup-github-actions.sh` or `.ps1` with corrected subject claim.
- Confirm repository variables are set exactly as emitted by script output.

## 3. Deploy ARC into AKS

- Configure `infra/demo/terraform.tfvars` for single-flow orchestration:
- `arc_bootstrap_enabled = true`
- `arc_bootstrap_execution_mode = "azure-control-plane"` (or `"gitops"` when explicitly required)
- `arc_bootstrap_script_shell = "bash"` or `"powershell"`
- runner scope/config inputs (`arc_bootstrap_runner_scope`, `arc_bootstrap_config_url`, replica bounds)
- Run the default Terraform-driven deployment flow from `infra/demo`:

```bash
terraform init
terraform plan -out demo.tfplan
terraform apply -auto-approve demo.tfplan
```

- Confirm bootstrap mode is jump-host-free.
- Terraform-orchestrated Azure control plane execution (`az aks command invoke`) is the default, or GitOps in-cluster reconciliation can be selected.
- Confirm idempotent re-run behavior:
- Re-running `terraform apply` without input/script changes should produce no ARC bootstrap re-execution.
- Bootstrap re-executes only when AKS identity changes, bootstrap script content changes, or bootstrap inputs change.
- Provision or enable a dedicated runner node pool (labels/taints distinct from workspace pools).
- Apply runner set configuration for this repo with node selector + tolerations targeting the runner pool.
- Confirm readiness:

```bash
kubectl get pods -n arc-systems
kubectl get autoscalingrunnersets -A
```

## 4. Validate private runner execution

- Trigger a workflow that targets ARC runner labels.
- Confirm job starts on AKS-hosted runner.
- Confirm scale-down after idle period.
- Confirm placement on runner pool only:
- Verify node labels for runner nodes.
- Verify runner pods include selector/tolerations matching runner pool taints.
- Verify runner pods are not scheduled to system/workspace pools.
- Validate ARC identity ACR permissions:
- Confirm `AcrPull` role assignment exists for the ARC identity.
- If runners publish images, confirm `AcrPush` role assignment exists.
- Run pull and (if applicable) push workflow paths to verify authorization.
- Validate runner node pool scaling.
- Confirm autoscaling bounds are independent from workspace pools.
- Confirm min nodes reaches `0` when supported, otherwise validate documented minimum.

Scale-to-minimum verification commands:

```bash
az aks nodepool show --resource-group <rg> --cluster-name <aks-name> --name <runner-pool>
az aks command invoke --resource-group <rg> --name <aks-name> --command "kubectl get pods -n arc-runners -o wide"
```

## 5. Enable devcontainer image CD workflow

- Ensure workflow file exists under `.github/workflows/` and path filter includes `devcontainer/**`.
- Update workflow variables with ACR login server from Terraform outputs.
- Push a change under `devcontainer/` and confirm build/push completion.

## 6. Validate script reorganisation

- Confirm control-plane scripts exist under `ops/scripts/`.
- Confirm only in-container scripts remain under `devcontainer/scripts/`.
- Validate all docs and workflows reference new control-plane script paths.

## 7. Rollback guidance

- Disable ARC runner set (scale min/max to 0) if runner instability is detected.
- Remove/disable faulty workflow while preserving federation config.
- Re-run script path verification if any operator docs fail due to stale paths.

## 8. End-to-End Validation Findings

Record the latest validation run outcome here:

- Terraform apply status:
- ARC controller readiness status:
- Runner set reconciliation status:
- OIDC workflow auth status:
- Devcontainer image publish status:

## 9. Success Criteria Evidence Capture

### SC-001 / SC-002 / SC-007 / SC-008 / SC-009

- Total runner validation runs:
- Successful runs on AKS-hosted private runner label:
- Runner start latency samples (seconds):
- ACR pull/push auth verification results:
- Node placement validation results:
- Idle scale-down observations:

### SC-003 / SC-004 / SC-005 / SC-006

- OIDC-only auth verification (no client secret evidence):
- Devcontainer build+push duration samples:
- Federation setup duration samples:
- Path-reference integrity checks (README/devcontainer/runbook/workflows):

## 10. Final Acceptance Evidence Matrix

| Requirement/SC | Evidence Artifact | Result | Notes |
| --- | --- | --- | --- |
| FR-001 .. FR-018 | Terraform plans, scripts, docs, workflows | Pending | Fill per implementation |
| SC-001 .. SC-010 | Validation logs and timings | Pending | Fill per validation run |
