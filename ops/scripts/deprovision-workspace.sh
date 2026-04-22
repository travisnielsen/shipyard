#!/usr/bin/env bash
# deprovision-workspace.sh — tear down a user's dev workspace namespace and storage class.
#
# Usage:
#   ./deprovision-workspace.sh <username> <storage-account-name> [--delete-data] [--developer-identity <upn-or-object-id>]
#
# What this does:
#   1. Deletes the namespace devcontainer-<username> (cascades to all namespaced resources:
#      Deployment, PVC, ResourceQuota, LimitRange, pods, etc.)
#   2. Waits for the namespace to be fully removed
#   3. Deletes the cluster-scoped StorageClass devcontainer-azurefile-mi-<username>
#
# By default the Azure File Share data is retained. Pass --delete-data to delete
# the per-user Azure File Share as well (irreversible).
#
# Requirements:
#   - kubectl configured against the target AKS cluster
#   - Azure CLI logged in with permission to delete Azure file shares

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./deprovision-workspace.sh <username> <storage-account-name> [--delete-data] [--developer-identity <upn-or-object-id>]

Environment overrides:
  DEV_WORKSPACE_DEVELOPER_IDENTITY   Developer UPN or object ID for RBAC cleanup
  WORKSPACE_AKS_NAMESPACE_ROLE       Defaults to 'Azure Kubernetes Service RBAC Writer'
  WORKSPACE_STORAGE_ROLE             Defaults to 'Storage File Data SMB Share Contributor'
EOF
}

[[ $# -lt 2 ]] && usage && exit 1

USERNAME="$1"
STORAGE_ACCOUNT_NAME="$2"
shift 2

DELETE_DATA="false"
DEVELOPER_IDENTITY="${DEV_WORKSPACE_DEVELOPER_IDENTITY:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-data)
      DELETE_DATA="true"
      shift
      ;;
    --developer-identity)
      [[ $# -lt 2 ]] && echo "ERROR: --developer-identity requires a value." && exit 1
      DEVELOPER_IDENTITY="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument '$1'."
      usage
      exit 1
      ;;
  esac
done

NAMESPACE="devcontainer-${USERNAME}"
STORAGE_CLASS_NAME="devcontainer-azurefile-mi-${USERNAME}"
SHARE_NAME="devcontainer-${USERNAME}"
WORKSPACE_AKS_NAMESPACE_ROLE="${WORKSPACE_AKS_NAMESPACE_ROLE:-Azure Kubernetes Service RBAC Writer}"
WORKSPACE_STORAGE_ROLE="${WORKSPACE_STORAGE_ROLE:-Storage File Data SMB Share Contributor}"

is_guid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

resolve_developer_object_id() {
  local identity="$1"
  if [[ -z "$identity" && "$USERNAME" == *"@"* ]]; then
    identity="$USERNAME"
  fi

  if [[ -z "$identity" ]]; then
    return 1
  fi

  if is_guid "$identity"; then
    echo "$identity"
    return 0
  fi

  az ad user show --id "$identity" --query id --output tsv 2>/dev/null || true
}

delete_role_assignment_if_exists() {
  local scope="$1"
  local role_name="$2"
  local principal_id="$3"

  mapfile -t assignment_ids < <(az role assignment list \
    --scope "$scope" \
    --assignee-object-id "$principal_id" \
    --role "$role_name" \
    --query '[].id' \
    --output tsv 2>/dev/null || true)

  if [[ "${#assignment_ids[@]}" -eq 0 ]]; then
    return 0
  fi

  for assignment_id in "${assignment_ids[@]}"; do
    az role assignment delete --ids "$assignment_id" --output none >/dev/null || true
  done
}

echo "==> Deprovisioning workspace for '${USERNAME}'"
echo "    Namespace : ${NAMESPACE}"
echo "    StorageClass : ${STORAGE_CLASS_NAME}"
echo "    File share   : ${SHARE_NAME}"
echo ""

AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-}"
if [[ -z "${AKS_RESOURCE_GROUP}" || -z "${AKS_CLUSTER_NAME}" ]]; then
  mapfile -t AKS_DISCOVERED < <(az aks list --query "[].join('|',[resourceGroup,name])" -o tsv 2>/dev/null || true)
  if [[ "${#AKS_DISCOVERED[@]}" -eq 1 ]]; then
    AKS_RESOURCE_GROUP="${AKS_DISCOVERED[0]%|*}"
    AKS_CLUSTER_NAME="${AKS_DISCOVERED[0]#*|}"
  fi
fi

AKS_RESOURCE_ID=""
if [[ -n "${AKS_RESOURCE_GROUP}" && -n "${AKS_CLUSTER_NAME}" ]]; then
  AKS_RESOURCE_ID="$(az aks show --resource-group "${AKS_RESOURCE_GROUP}" --name "${AKS_CLUSTER_NAME}" --query id --output tsv 2>/dev/null || true)"
fi

STORAGE_ACCOUNT_ID="$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --query id --output tsv 2>/dev/null || true)"
DEVELOPER_OBJECT_ID="$(resolve_developer_object_id "${DEVELOPER_IDENTITY}")"

if [[ -n "${DEVELOPER_OBJECT_ID}" && -n "${AKS_RESOURCE_ID}" ]]; then
  NAMESPACE_SCOPE="${AKS_RESOURCE_ID}/namespaces/${NAMESPACE}"
  echo "--> Removing namespace-scoped AKS RBAC assignment(s) for developer..."
  delete_role_assignment_if_exists "${NAMESPACE_SCOPE}" "${WORKSPACE_AKS_NAMESPACE_ROLE}" "${DEVELOPER_OBJECT_ID}"
else
  echo "INFO: Skipping AKS RBAC cleanup (set AKS_RESOURCE_GROUP/AKS_CLUSTER_NAME and developer identity for full cleanup)."
fi

if [[ -n "${DEVELOPER_OBJECT_ID}" && -n "${STORAGE_ACCOUNT_ID}" ]]; then
  SHARE_SCOPE="${STORAGE_ACCOUNT_ID}/fileServices/default/fileshares/${SHARE_NAME}"
  echo "--> Removing share-scoped storage RBAC assignment(s) for developer..."
  delete_role_assignment_if_exists "${SHARE_SCOPE}" "${WORKSPACE_STORAGE_ROLE}" "${DEVELOPER_OBJECT_ID}"
else
  echo "INFO: Skipping storage RBAC cleanup (could not resolve storage account ID and/or developer identity)."
fi

# 1. Check namespace exists before proceeding
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "WARNING: Namespace '${NAMESPACE}' not found — it may have already been deleted."
else
  echo "--> Deleting namespace '${NAMESPACE}' (cascades to all namespaced resources)..."
  kubectl delete namespace "${NAMESPACE}"

  echo "--> Waiting for namespace deletion to complete..."
  kubectl wait --for=delete namespace/"${NAMESPACE}" --timeout=120s \
    && echo "    Namespace deleted." \
    || echo "    WARNING: namespace deletion timed out — check 'kubectl get namespace ${NAMESPACE}'"
fi

# 2. Delete the cluster-scoped StorageClass
if ! kubectl get storageclass "${STORAGE_CLASS_NAME}" >/dev/null 2>&1; then
  echo "INFO: StorageClass '${STORAGE_CLASS_NAME}' not found — skipping."
else
  echo "--> Deleting StorageClass '${STORAGE_CLASS_NAME}'..."
  kubectl delete storageclass "${STORAGE_CLASS_NAME}"
  echo "    StorageClass deleted."
fi

# 3. Optionally delete the Azure File Share data
if [[ "${DELETE_DATA}" == "true" ]]; then
  echo ""
  echo "WARNING: --delete-data was specified."
  echo "  This will permanently delete Azure File Share '${SHARE_NAME}'."
  echo "  All workspace data for '${USERNAME}' will be lost."
  echo ""
  read -r -p "Type the username '${USERNAME}' to confirm permanent data deletion: " CONFIRM
  if [[ "${CONFIRM}" != "${USERNAME}" ]]; then
    echo "Confirmation did not match. Azure File Share retained."
  else
    az storage share-rm delete \
      --storage-account "${STORAGE_ACCOUNT_NAME}" \
      --name "${SHARE_NAME}" \
      --output none \
      2>/dev/null \
      && echo "    Azure File Share '${SHARE_NAME}' deleted." \
      || echo "    WARNING: Share deletion failed or share not found — check manually."
  fi
else
  echo "--> Retaining Azure File Share '${SHARE_NAME}' (data preserved)."
  echo "    To permanently delete the data, rerun with --delete-data"
  echo "    or delete the share manually in your storage account."
fi

echo ""
echo "==> Deprovision complete for '${USERNAME}'."
