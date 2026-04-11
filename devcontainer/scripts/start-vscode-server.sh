#!/usr/bin/env bash
set -euo pipefail

# START_MODE controls which runtime mode is launched:
#   idle    (default) — keep container running for AKS Kubernetes attach workflow
#   tunnel            — VS Code Remote Tunnels via the 'code' CLI (ACA primary path)
START_MODE="${START_MODE:-idle}"
WORKDIR="${DEVCONTAINER_WORKDIR:-/workspaces}"
TUNNEL_NAME="${TUNNEL_NAME:-}"

mkdir -p "${WORKDIR}"

if [[ "${START_MODE}" == "tunnel" ]]; then
  echo "Starting VS Code Remote Tunnels (START_MODE=tunnel)..."
  echo "  Tunnel name : ${TUNNEL_NAME:-<auto-assigned>}"
  echo "  Workdir     : ${WORKDIR}"
  echo ""
  echo "  Once registered, open the printed vscode.dev URL in VS Code"
  echo "  (Remote - Tunnels extension) or a browser."
  echo ""
  TUNNEL_ARGS=(
    tunnel
    --accept-server-license-terms
    --disable-telemetry
    --log info
  )
  [[ -n "${TUNNEL_NAME}" ]] && TUNNEL_ARGS+=(--name "${TUNNEL_NAME}")
  exec code "${TUNNEL_ARGS[@]}"
else
  echo "Starting idle runtime (START_MODE=idle) for Kubernetes attach..."
  exec tail -f /dev/null
fi
