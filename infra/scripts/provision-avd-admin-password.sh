#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: AVD_KEY_VAULT_NAME=<name> AVD_RESOURCE_GROUP_NAME=<rg> AVD_ADMIN_PASSWORD=<password> AVD_SESSION_HOST_COUNT=<count> $0"
  echo ""
  echo "Temporarily enables public access on the AVD Key Vault, provisions the"
  echo "AVD admin password secret(s), then disables public access again."
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  fi
}

KEY_VAULT_NAME="${AVD_KEY_VAULT_NAME:-}"
RESOURCE_GROUP_NAME="${AVD_RESOURCE_GROUP_NAME:-}"
SESSION_HOST_COUNT="${AVD_SESSION_HOST_COUNT:-1}"
PASSWORD="${AVD_ADMIN_PASSWORD:-}"

if [[ -z "$KEY_VAULT_NAME" || -z "$RESOURCE_GROUP_NAME" || -z "$PASSWORD" ]]; then
  echo "ERROR: AVD_KEY_VAULT_NAME, AVD_RESOURCE_GROUP_NAME, and AVD_ADMIN_PASSWORD are required." >&2
  usage
  exit 1
fi

if ! [[ "$SESSION_HOST_COUNT" =~ ^[0-9]+$ ]] || [[ "$SESSION_HOST_COUNT" -lt 1 ]]; then
  echo "ERROR: AVD_SESSION_HOST_COUNT must be an integer >= 1." >&2
  exit 1
fi

require_cmd az

echo "::add-mask::$PASSWORD"

cleanup() {
  echo "Disabling public network access on Key Vault: $KEY_VAULT_NAME"
  az keyvault update \
    --name "$KEY_VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --public-network-access Disabled \
    --default-action Deny \
    --bypass None \
    --only-show-errors \
    1>/dev/null
}

trap cleanup EXIT

echo "Temporarily enabling public network access on Key Vault: $KEY_VAULT_NAME"
az keyvault update \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --public-network-access Enabled \
  --default-action Allow \
  --bypass AzureServices \
  --only-show-errors \
  1>/dev/null

echo "Provisioning AVD password secret(s) in Key Vault"
for ((i = 0; i < SESSION_HOST_COUNT; i++)); do
  index=$(printf '%02d' "$i")
  secret_name="avd-admin-password-sh${index}"
  az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$secret_name" \
    --value "$PASSWORD" \
    --only-show-errors \
    1>/dev/null
  echo "Updated secret: $secret_name"
done

echo "Completed Key Vault secret provisioning for $SESSION_HOST_COUNT host(s)."
