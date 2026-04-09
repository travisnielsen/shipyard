# Devcontainer Package

This folder contains a deployable package for remote development workspaces.

## Contents

- `Dockerfile`: base image with common dev tools plus `code-server`.
- `scripts/start-vscode-server.sh`: container entrypoint to launch VS Code server.
- `scripts/healthcheck.sh`: basic readiness check.
- `manifests/`: starter deployment manifests for AKS and Azure Container Apps.

## Build

```bash
docker build -t remote-devcontainer:latest .
```

## Run Locally

```bash
docker run --rm -it \
  -p 8443:8443 \
  -e DEVCONTAINER_PASSWORD='ChangeMeNow!' \
  remote-devcontainer:latest
```

Then browse to `http://localhost:8443`.
