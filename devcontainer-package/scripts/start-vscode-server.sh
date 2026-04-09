#!/usr/bin/env bash
set -euo pipefail

PORT="${DEVCONTAINER_PORT:-8443}"
HOST="${DEVCONTAINER_HOST:-0.0.0.0}"
WORKDIR="${DEVCONTAINER_WORKDIR:-/workspaces}"
PASSWORD="${DEVCONTAINER_PASSWORD:-}"

if [[ -z "${PASSWORD}" ]]; then
  echo "DEVCONTAINER_PASSWORD is required to start code-server."
  exit 1
fi

mkdir -p "${WORKDIR}"
export PASSWORD

exec code-server \
  --bind-addr "${HOST}:${PORT}" \
  --auth password \
  --disable-telemetry \
  --disable-update-check \
  "${WORKDIR}"
