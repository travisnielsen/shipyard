#!/usr/bin/env bash
set -euo pipefail

echo "Running devcontainer tool version smoke tests..."

check_cmd() {
  local name="$1"
  local cmd="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $name"
    exit 1
  fi

  echo "--- ${name}"
  eval "$cmd"
}

check_cmd python3 "python3 --version"
check_cmd pip "pip --version"
check_cmd uv "uv --version"
check_cmd uvx "uvx --version"

check_cmd ruff "ruff --version"
check_cmd black "black --version"
check_cmd isort "isort --version"
check_cmd mypy "mypy --version"
check_cmd pytest "pytest --version"
check_cmd pre-commit "pre-commit --version"

check_cmd node "node --version"
check_cmd npm "npm --version"
check_cmd pnpm "pnpm --version"
check_cmd yarn "yarn --version"
check_cmd tsc "tsc --version"
check_cmd eslint "eslint --version"
check_cmd prettier "prettier --version"
check_cmd create-vite "create-vite --help | head -n 1"

check_cmd az "az version --output json | jq -r '.\"azure-cli\"'"
check_cmd pwsh "pwsh --version"
check_cmd gh "gh --version | head -n 1"
check_cmd git "git --version"

echo "Smoke tests passed."
