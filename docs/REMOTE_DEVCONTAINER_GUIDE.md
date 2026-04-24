# Remote Dev Container: Key Differences from Local Development

This guide explains what to expect when working inside the AKS-hosted remote dev container this repo provides, compared to standard local development.

## Access & Connectivity

| | Remote (this repo) | Local |
|---|---|---|
| Access method | VS Code attaches via `kubectl port-forward` through an AVD/VDI session | Direct filesystem access |
| Authentication | Azure RBAC + `kubelogin` token (expires, must refresh) | None / local OS auth |
| Network | All traffic on private subnets, no internet routes | Unrestricted outbound |

## What You CAN Do

- Full terminal, git, and CLI access — Azure CLI, `gh`, `kubectl`, `pwsh`, and `az` are all pre-installed in the image
- Install packages with `sudo` — the `vscode` user has passwordless `sudo`
- Run code-server (VS Code in browser) on port 8443, or attach VS Code Desktop via the Dev Containers extension
- Commit and push to git — same workflow as local development

## What You CANNOT Do (or is restricted)

- **No Docker-in-Docker** — the container runs with `allowPrivilegeEscalation: false`, drops all Linux capabilities, and runs as non-root (UID 1000). Building images inside the container is not possible without explicit `docker.sock` sharing, which is not configured.
- **No listening on arbitrary ports** — only port 8443 is declared and exposed.
- **Resource caps** — hard limits of 2 CPU / 4 GB RAM per container; namespace quota caps at 4 CPU / 8 GB RAM total.
- **No direct localhost access** — you must use `kubectl port-forward` to reach services running inside the pod from your local machine.

## What is Saved Across Sessions

Everything under `/workspaces` is backed by a **10 GB Azure Files persistent volume** (SMB, managed identity auth). This survives pod restarts and image updates:

- Cloned repositories and source code
- Any files written under `/workspaces`

## What is NOT Saved (Ephemeral)

Everything outside `/workspaces` is tied to the container image and is **reset on pod restart or image update**:

- Packages installed at runtime (apt, pip, npm globals)
- Shell history stored in `/home/vscode` (home directory is not on the persistent volume)
- In-memory auth tokens (`az login`, `kubelogin` caches stored outside `/workspaces`)
- Any process state, background jobs, or tmux sessions

> **Practical tip**: Put any persistent config (`.gitconfig`, shell dotfiles, VS Code Settings Sync) under `/workspaces`, or rely on the pre-baked image. If you need a tool not in the image, ask the platform operator to add it to the Dockerfile — runtime installs will not survive a pod recycle.

## Related Documentation

- [AKS DevContainer Onboarding Guide](AKS_DEVCONTAINER_ONBOARDING.md)
- [Brownfield Deployment Runbook](DEPLOYMENT_RUNBOOK_BROWNFIELD.md)
- [Port Requirements](PORT_REQUIREMENTS.md)
- [Day 2 Operations](DAY2_OPERATIONS.md)
