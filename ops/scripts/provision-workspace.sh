#!/usr/bin/env bash
# provision-workspace.sh — create an isolated dev workspace namespace for a single user.
#
# Usage:
#   ./provision-workspace.sh <username> <storage-resource-group> <storage-account-name> [<share-name>]
#
# What this does:
#   1. Creates a dedicated namespace:     devcontainer-<username>
#   2. Ensures SMB OAuth is enabled on the storage account for MI-based Azure Files auth
#   3. Creates a per-user StorageClass using managed identity auth
#   4. Applies namespace LimitRange + ResourceQuota
#   5. Creates a PersistentVolumeClaim in the namespace (dynamic provisioning)
#   6. Deploys the dev-workspace Deployment into the namespace
#
# Requirements:
#   - kubectl configured against the target AKS cluster
#   - Azure CLI (az) logged in with rights to update the storage account
#   - AKS kubelet identity must have Storage File Data SMB MI Admin on the storage account
#   - AKS must support Azure Files managed identity mount mode
#   - If your subscription has multiple AKS clusters, set:
#       AKS_RESOURCE_GROUP=<rg> AKS_CLUSTER_NAME=<name>

set -euo pipefail

USERNAME="${1:?Usage: $0 <username> <storage-resource-group> <storage-account-name> [<share-name>]}"
STORAGE_RESOURCE_GROUP="${2:?Usage: $0 <username> <storage-resource-group> <storage-account-name> [<share-name>]}"
STORAGE_ACCOUNT_NAME="${3:?Usage: $0 <username> <storage-resource-group> <storage-account-name> [<share-name>]}"
SHARE_NAME="${4:-devcontainer-${USERNAME}}"

NAMESPACE="devcontainer-${USERNAME}"
STORAGE_CLASS_NAME="devcontainer-azurefile-mi-${USERNAME}"
MANIFESTS_DIR="$(cd "$(dirname "$0")/../../devcontainer/manifests" && pwd)"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}"
    exit 1
  fi
}

fail() {
  echo "ERROR: $*"
  exit 1
}

echo "==> Provisioning workspace for '${USERNAME}' in namespace '${NAMESPACE}'"
echo "    Storage RG      : ${STORAGE_RESOURCE_GROUP}"
echo "    Storage account : ${STORAGE_ACCOUNT_NAME}"
echo "    File share      : ${SHARE_NAME}"
echo "    StorageClass    : ${STORAGE_CLASS_NAME}"
echo ""

# 0. Fail-fast prerequisite checks for MI-based Azure Files mount mode.
require_cmd kubectl
require_cmd az

# Resolve workspace image early so we can display it in the banner.
WORKSPACE_IMAGE="${DEV_WORKSPACE_IMAGE:-}"
if [[ -z "${WORKSPACE_IMAGE}" ]]; then
  mapfile -t ACR_SERVERS < <(az acr list --resource-group "${STORAGE_RESOURCE_GROUP}" --query "[].loginServer" --output tsv 2>/dev/null || true)
  if [[ "${#ACR_SERVERS[@]}" -eq 1 && -n "${ACR_SERVERS[0]}" ]]; then
    WORKSPACE_IMAGE="${ACR_SERVERS[0]}/remote-devcontainer:latest"
  elif [[ "${#ACR_SERVERS[@]}" -gt 1 ]]; then
    fail "Multiple ACR registries found in resource group '${STORAGE_RESOURCE_GROUP}'. Set DEV_WORKSPACE_IMAGE explicitly (for example: '<acr-login-server>/remote-devcontainer:latest')."
  else
    fail "Could not resolve a workspace image automatically. Set DEV_WORKSPACE_IMAGE (for example: '<acr-login-server>/remote-devcontainer:latest')."
  fi
fi
echo "    Workspace image : ${WORKSPACE_IMAGE}"

echo "--> Validating AKS managed-identity storage prerequisites..."

SERVER_MAJOR="$(kubectl version -o jsonpath='{.serverVersion.major}' 2>/dev/null | tr -cd '0-9' || true)"
SERVER_MINOR_RAW="$(kubectl version -o jsonpath='{.serverVersion.minor}' 2>/dev/null || true)"
SERVER_MINOR="$(echo "${SERVER_MINOR_RAW}" | tr -cd '0-9')"

[[ -z "${SERVER_MAJOR}" || -z "${SERVER_MINOR}" ]] && \
  fail "Could not detect Kubernetes server version from current kubectl context. Run 'az aks get-credentials --resource-group <aks-rg> --name <aks-name> --overwrite-existing' and retry."

if [[ "${SERVER_MAJOR}" -lt 1 || ( "${SERVER_MAJOR}" -eq 1 && "${SERVER_MINOR}" -lt 34 ) ]]; then
  fail "AKS Kubernetes version ${SERVER_MAJOR}.${SERVER_MINOR_RAW} does not meet minimum 1.34 for Azure Files managed identity mount mode."
fi

# Pre-check: ensure the current identity can read CSI driver resources.
CAN_I_CSI="$(kubectl auth can-i get csidrivers.storage.k8s.io 2>&1 || true)"
if [[ "${CAN_I_CSI}" != "yes" ]]; then
  fail "Current identity cannot get 'csidrivers.storage.k8s.io' from the cluster. On AKS with Azure RBAC enabled, assign 'Azure Kubernetes Service RBAC Cluster Admin' (or a role that grants this resource) and refresh credentials."
fi

CSI_CHECK_OUTPUT="$(kubectl get csidriver file.csi.azure.com -o name 2>&1 || true)"
if [[ -z "${CSI_CHECK_OUTPUT}" || "${CSI_CHECK_OUTPUT}" == *"NotFound"* || "${CSI_CHECK_OUTPUT}" == *"not found"* ]]; then
  if [[ "${CSI_CHECK_OUTPUT}" == *"forbidden"* || "${CSI_CHECK_OUTPUT}" == *"does not have access"* ]]; then
    fail "Unable to verify Azure Files CSI driver because this identity cannot access cluster-scoped CSI resources. Assign 'Azure Kubernetes Service RBAC Cluster Admin' (or equivalent) and refresh credentials."
  fi
  fail "Azure Files CSI driver (file.csi.azure.com) is not available in the current cluster."
fi

# Dynamic Azure Files provisioning requires the controller — either as a
# standalone deployment (AKS < 1.34) or embedded in the node DaemonSet
# (AKS >= 1.34 controllerless model).
if ! kubectl get deployment csi-azurefile-controller -n kube-system -o name >/dev/null 2>&1; then
  NODE_DS_READY="$(kubectl get daemonset csi-azurefile-node -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
  if [[ "${NODE_DS_READY}" -eq 0 ]]; then
    fail "Azure File CSI controller deployment is missing and the csi-azurefile-node DaemonSet has no ready pods. Dynamic Azure Files provisioning will not work until this AKS addon issue is resolved."
  fi
  echo "    Azure File CSI controller running in node DaemonSet (controllerless mode)."
else
  echo "    Azure File CSI controller deployment verified."
fi

if [[ -z "${AKS_RESOURCE_GROUP:-}" || -z "${AKS_CLUSTER_NAME:-}" ]]; then
  mapfile -t AKS_DISCOVERED < <(az aks list --query "[].join('|',[resourceGroup,name])" -o tsv 2>/dev/null || true)

  if [[ "${#AKS_DISCOVERED[@]}" -eq 0 ]]; then
    fail "No AKS clusters were discovered in the current Azure context. Set AKS_RESOURCE_GROUP and AKS_CLUSTER_NAME."
  fi

  if [[ "${#AKS_DISCOVERED[@]}" -gt 1 ]]; then
    echo "Discovered multiple AKS clusters:" >&2
    printf '  - %s\n' "${AKS_DISCOVERED[@]}" >&2
    fail "Set AKS_RESOURCE_GROUP and AKS_CLUSTER_NAME explicitly to continue."
  fi

  AKS_RESOURCE_GROUP="${AKS_DISCOVERED[0]%|*}"
  AKS_CLUSTER_NAME="${AKS_DISCOVERED[0]#*|}"
fi

KUBELET_OBJECT_ID="$(az aks show \
  --resource-group "${AKS_RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER_NAME}" \
  --query "coalesce(identityProfile.kubeletidentity.objectId, identityProfile.kubeletidentity.object_id)" \
  --output tsv 2>/dev/null || true)"

[[ -z "${KUBELET_OBJECT_ID}" ]] && \
  fail "Could not resolve AKS kubelet identity object ID for ${AKS_RESOURCE_GROUP}/${AKS_CLUSTER_NAME}."

STORAGE_ACCOUNT_ID="$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${STORAGE_RESOURCE_GROUP}" \
  --query id --output tsv 2>/dev/null || true)"

[[ -z "${STORAGE_ACCOUNT_ID}" ]] && \
  fail "Could not resolve storage account ${STORAGE_ACCOUNT_NAME} in ${STORAGE_RESOURCE_GROUP}."

echo "    Validating RBAC roles on storage account..."
REQUIRED_ROLES=("Storage File Data SMB MI Admin" "Storage Account Contributor" "Storage File Data SMB Share Contributor")
MISSING_ROLES=()
for role in "${REQUIRED_ROLES[@]}"; do
  count="$(az role assignment list \
    --scope "${STORAGE_ACCOUNT_ID}" \
    --assignee-object-id "${KUBELET_OBJECT_ID}" \
    --role "${role}" \
    --query 'length(@)' \
    --output tsv 2>/dev/null || echo 0)"
  if [[ "${count}" == "0" ]]; then
    MISSING_ROLES+=("${role}")
  fi
done

if [[ "${#MISSING_ROLES[@]}" -gt 0 ]]; then
  fail "AKS kubelet identity is missing required RBAC roles on ${STORAGE_ACCOUNT_NAME}: [$(IFS=', '; echo "${MISSING_ROLES[*]}")]. Assign these roles before provisioning."
fi

# Check namespace availability
echo "    Checking namespace availability..."
if kubectl get namespace "${NAMESPACE}" -o name >/dev/null 2>&1; then
  echo "    WARNING: Namespace '${NAMESPACE}' already exists. Proceeding with provisioning."
fi

echo "Preflight validation complete."
echo ""

# 1. Namespace
echo "--> Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 2. Enable SMB OAuth for MI-based Azure Files authentication (idempotent)
echo "--> Enabling SMB OAuth on storage account '${STORAGE_ACCOUNT_NAME}'..."
az storage account update \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${STORAGE_RESOURCE_GROUP}" \
  --enable-smb-oauth true \
  --output none

SMB_OAUTH_JSON="$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${STORAGE_RESOURCE_GROUP}" \
  --query '{legacy:enableSmbOauth,new:azureFilesIdentityBasedAuthentication.smbOAuthSettings.isSmbOAuthEnabled}' \
  --output json 2>/dev/null || echo '{}')"
SMB_LEGACY="$(echo "${SMB_OAUTH_JSON}" | grep -o '"legacy":[^,}]*' | head -1 | sed 's/.*://' | tr -d ' "' || true)"
SMB_NEW="$(echo "${SMB_OAUTH_JSON}" | grep -o '"new":[^,}]*' | head -1 | sed 's/.*://' | tr -d ' "' || true)"
if [[ "${SMB_LEGACY}" != "true" && "${SMB_NEW}" != "true" ]]; then
  fail "Storage account SMB OAuth is not enabled after update call."
fi

# 3. Per-user managed-identity StorageClass (cluster-scoped)
echo "--> Creating StorageClass ${STORAGE_CLASS_NAME}..."
sed \
  -e "s/name: devcontainer-azurefile-mi/name: ${STORAGE_CLASS_NAME}/g" \
  -e "s/REPLACE_STORAGE_RESOURCE_GROUP/${STORAGE_RESOURCE_GROUP}/g" \
  -e "s/REPLACE_STORAGE_ACCOUNT_NAME/${STORAGE_ACCOUNT_NAME}/g" \
  -e "s/REPLACE_SHARE_NAME/${SHARE_NAME}/g" \
  "${MANIFESTS_DIR}/storageclass-azurefile-mi.yaml" | kubectl apply -f -

# 4. LimitRange
echo "--> Applying LimitRange..."
sed "s/namespace: devcontainers/namespace: ${NAMESPACE}/g" \
  "${MANIFESTS_DIR}/limit-range.yaml" | kubectl apply -f -

# 5. ResourceQuota
echo "--> Applying ResourceQuota..."
sed "s/namespace: devcontainers/namespace: ${NAMESPACE}/g" \
  "${MANIFESTS_DIR}/resource-quota.yaml" | kubectl apply -f -

# 6. PersistentVolumeClaim (dynamic provisioning through per-user StorageClass)
echo "--> Creating PersistentVolumeClaim in ${NAMESPACE}..."
sed \
  -e "s/namespace: devcontainers/namespace: ${NAMESPACE}/g" \
  -e "s/storageClassName: azurefile-csi/storageClassName: ${STORAGE_CLASS_NAME}/g" \
  "${MANIFESTS_DIR}/pvc.yaml" | kubectl apply -f -

# 7. Deployment
echo "--> Deploying dev-workspace in ${NAMESPACE}..."
sed \
  -e "s/namespace: devcontainers/namespace: ${NAMESPACE}/g" \
  -e "s|image: myacr.azurecr.io/remote-devcontainer:latest|image: ${WORKSPACE_IMAGE}|g" \
  "${MANIFESTS_DIR}/dev-workspace-deployment.yaml" | kubectl apply -f -

# 8. Wait for rollout
echo "--> Waiting for deployment rollout in ${NAMESPACE}..."
if ! kubectl rollout status deployment/dev-workspace -n "${NAMESPACE}" --timeout=240s 2>&1; then
  echo ""
  echo "--- Diagnostics ---"
  echo "Pods in ${NAMESPACE}:"
  kubectl get pods -n "${NAMESPACE}" -o wide 2>&1 | sed 's/^/  /'
  echo "Events in ${NAMESPACE}:"
  kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' 2>&1 | tail -15 | sed 's/^/  /'
  echo "PVC status in ${NAMESPACE}:"
  kubectl get pvc -n "${NAMESPACE}" -o wide 2>&1 | sed 's/^/  /'
  echo "--- End Diagnostics ---"
  fail "dev-workspace deployment did not become ready within timeout. See diagnostics above."
fi

echo ""
echo "==> Done. To connect:"
echo ""
echo "    Option A — VS Code Kubernetes extension (recommended, no internet required from pod):"
echo "      1. Open VS Code locally with the 'Dev Containers' + 'Kubernetes' extensions installed."
echo "      2. Set the current kubectl namespace so the Dev Containers extension can see the pod:"
echo "           kubectl config set-context --current --namespace=${NAMESPACE}"
echo "      3. Open the Command Palette (F1) and run:"
echo "           Dev Containers: Attach to Running Kubernetes Container..."
echo "         OR: Kubernetes explorer -> expand cluster -> right-click the pod -> Attach Visual Studio Code"
echo "      4. VS Code will not discover the pod unless kubectl is set to the correct namespace."
echo "      5. VS Code Server installs itself inside the pod automatically — no code-server credentials needed."
echo "      6. Reference attached-container-config.json in manifests/ for recommended extension/settings defaults."
echo ""
echo "    Option B — VS Code Remote Tunnels (requires outbound internet from pod to Microsoft tunnel service):"
echo "      kubectl exec -n ${NAMESPACE} deploy/dev-workspace -- code tunnel --accept-server-license-terms"
echo "      Then open the printed vscode.dev URL in VS Code or a browser."
echo ""
echo "    To tail logs:"
echo "      kubectl logs -n ${NAMESPACE} deploy/dev-workspace -f"
