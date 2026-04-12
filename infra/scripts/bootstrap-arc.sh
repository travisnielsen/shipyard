#!/usr/bin/env bash
set -euo pipefail

# ARC bootstrap scaffold.
# Expected env vars are passed by Terraform local-exec.
: "${AKS_CLUSTER_NAME:?AKS_CLUSTER_NAME is required}"
: "${AKS_RESOURCE_GROUP:?AKS_RESOURCE_GROUP is required}"
: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"

ARC_BOOTSTRAP_EXECUTION_MODE="${ARC_BOOTSTRAP_EXECUTION_MODE:-azure-control-plane}"
ARC_RUNNER_SCOPE="${ARC_RUNNER_SCOPE:-repository}"
ARC_RUNNER_CONFIG_URL="${ARC_RUNNER_CONFIG_URL:-}"
ARC_GITHUB_APP_ID="${ARC_GITHUB_APP_ID:-}"
ARC_GITHUB_APP_INSTALLATION_ID="${ARC_GITHUB_APP_INSTALLATION_ID:-}"
ARC_GITHUB_APP_PRIVATE_KEY="${ARC_GITHUB_APP_PRIVATE_KEY:-}"
ARC_RUNNER_LABELS="${ARC_RUNNER_LABELS:-shipyard-private,linux,aks}"
ARC_RUNNER_MIN_REPLICAS="${ARC_RUNNER_MIN_REPLICAS:-0}"
ARC_RUNNER_MAX_REPLICAS="${ARC_RUNNER_MAX_REPLICAS:-5}"
ARC_RUNNER_NODEPOOL_NAME="${ARC_RUNNER_NODEPOOL_NAME:-arc}"
ARC_RUNNER_IMAGE="${ARC_RUNNER_IMAGE:-ghcr.io/actions/actions-runner:latest}"
ARC_CONTROLLER_RELEASE_NAME="${ARC_CONTROLLER_RELEASE_NAME:-arc-controller}"
ARC_CONTROLLER_CHART_VERSION="${ARC_CONTROLLER_CHART_VERSION:-0.12.1}"
ARC_CONTROLLER_CHART_REF="${ARC_CONTROLLER_CHART_REF:-oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller}"
ARC_RUNNER_RELEASE_NAME="${ARC_RUNNER_RELEASE_NAME:-shipyard-runner-set}"
ARC_RUNNER_CHART_VERSION="${ARC_RUNNER_CHART_VERSION:-0.12.1}"
ARC_RUNNER_CHART_REF="${ARC_RUNNER_CHART_REF:-oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set}"
ARC_RUNNER_SECRET_NAME="${ARC_RUNNER_SECRET_NAME:-arc-runner-set-secret}"

echo "[bootstrap-arc] mode=${ARC_BOOTSTRAP_EXECUTION_MODE} cluster=${AKS_CLUSTER_NAME} rg=${AKS_RESOURCE_GROUP}"
echo "[bootstrap-arc] scope=${ARC_RUNNER_SCOPE} config_url=${ARC_RUNNER_CONFIG_URL} labels=${ARC_RUNNER_LABELS}"
echo "[bootstrap-arc] replicas=${ARC_RUNNER_MIN_REPLICAS}-${ARC_RUNNER_MAX_REPLICAS} nodepool=${ARC_RUNNER_NODEPOOL_NAME}"

if [[ "${ARC_BOOTSTRAP_EXECUTION_MODE}" == "gitops" ]]; then
  echo "[bootstrap-arc] gitops mode selected; no imperative install performed in scaffold."
  exit 0
fi

if ! command -v az >/dev/null 2>&1; then
  echo "[bootstrap-arc] az CLI is required for azure-control-plane mode" >&2
  exit 1
fi

if [[ -z "${ARC_RUNNER_CONFIG_URL}" ]]; then
  echo "[bootstrap-arc] ARC_RUNNER_CONFIG_URL is required in azure-control-plane mode" >&2
  exit 1
fi

if [[ -z "${ARC_GITHUB_APP_ID}" || -z "${ARC_GITHUB_APP_INSTALLATION_ID}" || -z "${ARC_GITHUB_APP_PRIVATE_KEY}" ]]; then
  echo "[bootstrap-arc] ARC_GITHUB_APP_ID, ARC_GITHUB_APP_INSTALLATION_ID, and ARC_GITHUB_APP_PRIVATE_KEY are required." >&2
  exit 1
fi

az account set --subscription "${AZURE_SUBSCRIPTION_ID}"

invoke_aks() {
  local command="$1"
  local result
  local remote_exit

  result="$(az aks command invoke \
    --resource-group "${AKS_RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --command "${command}" \
    --output json)"

  remote_exit="$(printf '%s' "${result}" | sed -n 's/.*"exitCode":[[:space:]]*\([-0-9][0-9]*\).*/\1/p' | head -n1)"
  if [[ -z "${remote_exit}" || "${remote_exit}" != "0" ]]; then
    echo "[bootstrap-arc] remote command failed (exitCode=${remote_exit:-unknown}): ${command}" >&2
    printf '%s\n' "${result}" >&2
    exit 1
  fi
}

# Namespace + controller install is idempotent through kubectl apply and helm upgrade --install.
invoke_aks "kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -"
invoke_aks "kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -"

private_key_indented="$(printf '%s\n' "${ARC_GITHUB_APP_PRIVATE_KEY}" | sed 's/^/    /')"

invoke_aks "kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARC_RUNNER_SECRET_NAME}
  namespace: arc-runners
type: Opaque
stringData:
  github_app_id: \"${ARC_GITHUB_APP_ID}\"
  github_app_installation_id: \"${ARC_GITHUB_APP_INSTALLATION_ID}\"
  github_app_private_key: |
${private_key_indented}
EOF"

invoke_aks "helm upgrade --install ${ARC_CONTROLLER_RELEASE_NAME} ${ARC_CONTROLLER_CHART_REF} --namespace arc-systems --version ${ARC_CONTROLLER_CHART_VERSION}"

invoke_aks "helm upgrade --install ${ARC_RUNNER_RELEASE_NAME} ${ARC_RUNNER_CHART_REF} --namespace arc-runners --version ${ARC_RUNNER_CHART_VERSION} -f - <<'EOF'
githubConfigUrl: ${ARC_RUNNER_CONFIG_URL}
githubConfigSecret: ${ARC_RUNNER_SECRET_NAME}
minRunners: ${ARC_RUNNER_MIN_REPLICAS}
maxRunners: ${ARC_RUNNER_MAX_REPLICAS}
template:
  spec:
    containers:
      - name: runner
        image: ${ARC_RUNNER_IMAGE}
    nodeSelector:
      kubernetes.azure.com/agentpool: ${ARC_RUNNER_NODEPOOL_NAME}
    tolerations:
      - key: workload
        operator: Equal
        value: github-runner
        effect: NoSchedule
EOF"

echo "[bootstrap-arc] ARC controller and runner set helm install commands completed."
