#!/usr/bin/env bash
# deprovision-workspace.sh — tear down a user's dev workspace namespace and storage class.
#
# Usage:
#   ./deprovision-workspace.sh <username> <storage-account-name> [--delete-data]
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

USERNAME="${1:?Usage: $0 <username> <storage-account-name> [--delete-data]}"
STORAGE_ACCOUNT_NAME="${2:?Usage: $0 <username> <storage-account-name> [--delete-data]}"
DELETE_DATA="${3:-}"

NAMESPACE="devcontainer-${USERNAME}"
STORAGE_CLASS_NAME="devcontainer-azurefile-mi-${USERNAME}"
SHARE_NAME="devcontainer-${USERNAME}"

echo "==> Deprovisioning workspace for '${USERNAME}'"
echo "    Namespace : ${NAMESPACE}"
echo "    StorageClass : ${STORAGE_CLASS_NAME}"
echo "    File share   : ${SHARE_NAME}"
echo ""

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
if [[ "${DELETE_DATA}" == "--delete-data" ]]; then
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
