#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <subscription-id> <github-owner> <github-repo> [subject-pattern] [app-name]"
  echo "Example subject-pattern: repo:owner/repo:ref:refs/heads/main"
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

SUBSCRIPTION_ID="$1"
GITHUB_OWNER="$2"
GITHUB_REPO="$3"
SUBJECT_PATTERN="${4:-repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/main}"
APP_NAME="${5:-shipyard-${GITHUB_OWNER}-${GITHUB_REPO}-gha}"
FED_NAME="github-${GITHUB_OWNER}-${GITHUB_REPO}-oidc"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  fi
}

require_cmd az

az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID="$(az account show --query tenantId -o tsv)"

APP_ID="$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
fi

APP_OBJECT_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"
SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)"
if [[ -z "$SP_OBJECT_ID" ]]; then
  SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
fi

EXISTS="$(az ad app federated-credential list --id "$APP_OBJECT_ID" --query "[?name=='$FED_NAME'] | length(@)" -o tsv)"
if [[ "$EXISTS" == "0" ]]; then
  TMP_JSON="$(mktemp)"
  cat > "$TMP_JSON" <<EOF
{
  "name": "$FED_NAME",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$SUBJECT_PATTERN",
  "description": "Shipyard GitHub OIDC federation",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
  az ad app federated-credential create --id "$APP_OBJECT_ID" --parameters "$TMP_JSON" >/dev/null
  rm -f "$TMP_JSON"
fi

echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "GITHUB_SUBJECT_PATTERN=$SUBJECT_PATTERN"
echo "ARC_RUNTIME_PRINCIPAL_ID=$SP_OBJECT_ID"
echo "FEDERATED_APP_OBJECT_ID=$APP_OBJECT_ID"
echo "NOTE=RBAC role assignments are managed by Terraform, not this setup script."
