#!/usr/bin/env bash
# setup-hooks.sh: Configures git to use the repo's .githooks directory.
# Run once after cloning: bash .githooks/setup-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

git config --local core.hooksPath .githooks
chmod +x "$REPO_ROOT"/.githooks/pre-commit
chmod +x "$REPO_ROOT"/.githooks/commit-msg
chmod +x "$REPO_ROOT"/.githooks/pre-push

echo "✅  Git hooks configured. Using: .githooks/"
echo "    pre-commit : runs Terraform fmt/validate (and tflint if installed) for infra changes"
echo "    commit-msg : enforces Conventional Commits format"
echo "    pre-push   : blocks direct pushes to main/master"
