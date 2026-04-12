#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TF_DIR}/.." && pwd)"

VAR_FILE="${TF_DIR}/terraform.tfvars"
RUNNER_IMAGE_REPO="actions-runner"
RUNNER_IMAGE_TAG=""
SKIP_BASE_APPLY="false"

usage() {
  cat <<'EOF'
Usage: deploy-arc-runner-image.sh [options]

Options:
  --var-file <path>          Terraform var-file to use (default: infra/terraform.tfvars)
  --runner-image-repo <name> Repository name inside ACR (default: actions-runner)
  --runner-image-tag <tag>   Image tag to publish/use (default: current git short SHA)
  --skip-base-apply          Skip the initial terraform apply and only run build + image switch apply
  -h, --help                 Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      if [[ "$2" = /* ]]; then
        VAR_FILE="$2"
      else
        VAR_FILE="${TF_DIR}/$2"
      fi
      shift 2
      ;;
    --runner-image-repo)
      RUNNER_IMAGE_REPO="$2"
      shift 2
      ;;
    --runner-image-tag)
      RUNNER_IMAGE_TAG="$2"
      shift 2
      ;;
    --skip-base-apply)
      SKIP_BASE_APPLY="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required." >&2
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required." >&2
  exit 1
fi

if [[ ! -f "${VAR_FILE}" ]]; then
  echo "Terraform var-file not found: ${VAR_FILE}" >&2
  exit 1
fi

if [[ -z "${RUNNER_IMAGE_TAG}" ]]; then
  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --short HEAD >/dev/null 2>&1; then
    RUNNER_IMAGE_TAG="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
  else
    RUNNER_IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
  fi
fi

cd "${TF_DIR}"

echo "[deploy-arc-runner-image] terraform init"
terraform init

echo "[deploy-arc-runner-image] terraform validate"
terraform validate

if [[ "${SKIP_BASE_APPLY}" != "true" ]]; then
  echo "[deploy-arc-runner-image] terraform apply (base infrastructure)"
  terraform apply -auto-approve -var-file="${VAR_FILE}"
fi

echo "[deploy-arc-runner-image] reading Terraform outputs"
ACR_LOGIN_SERVER="$(terraform output -raw acr_login_server)"
ACR_TASK_AGENTPOOL_NAME="$(terraform output -raw acr_task_agentpool_name 2>/dev/null || true)"

if [[ -z "${ACR_TASK_AGENTPOOL_NAME}" ]]; then
  echo "acr_task_agentpool_name output is empty. Ensure enable_private_acr_tasks=true and apply has completed." >&2
  exit 1
fi

ACR_NAME="${ACR_LOGIN_SERVER%%.*}"
TARGET_IMAGE="${ACR_LOGIN_SERVER}/${RUNNER_IMAGE_REPO}:${RUNNER_IMAGE_TAG}"

echo "[deploy-arc-runner-image] building ${TARGET_IMAGE} using private ACR Task pool ${ACR_TASK_AGENTPOOL_NAME}"
az acr build \
  --registry "${ACR_NAME}" \
  --agent-pool "${ACR_TASK_AGENTPOOL_NAME}" \
  --file "${REPO_ROOT}/infra/github-runner/Dockerfile.runner" \
  --image "${RUNNER_IMAGE_REPO}:${RUNNER_IMAGE_TAG}" \
  --image "${RUNNER_IMAGE_REPO}:latest" \
  "${REPO_ROOT}"

ARC_BOOTSTRAP_ENABLED="$(terraform output -raw arc_bootstrap_enabled 2>/dev/null || echo false)"

echo "[deploy-arc-runner-image] terraform apply (set arc_runner_image=${TARGET_IMAGE})"
if [[ "${ARC_BOOTSTRAP_ENABLED}" == "true" ]]; then
  terraform apply -auto-approve -var-file="${VAR_FILE}" -var "arc_runner_image=${TARGET_IMAGE}" -replace=terraform_data.arc_bootstrap[0]
else
  terraform apply -auto-approve -var-file="${VAR_FILE}" -var "arc_runner_image=${TARGET_IMAGE}"
fi

echo "[deploy-arc-runner-image] complete"
echo "Published image: ${TARGET_IMAGE}"
