#!/usr/bin/env bash
set -euo pipefail

START_MODE="${START_MODE:-idle}"

if [[ "${START_MODE}" == "tunnel" ]]; then
  # In tunnel mode there is no HTTP listener — verify the code process is alive instead.
  pgrep -x code >/dev/null
else
  # In idle mode the container is intentionally kept alive for VS Code attach.
  pgrep -f "tail -f /dev/null" >/dev/null
fi
