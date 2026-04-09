#!/usr/bin/env bash
set -euo pipefail

PORT="${DEVCONTAINER_PORT:-8443}"
curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null
