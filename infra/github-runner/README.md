# GitHub Actions Runner Image

Custom GitHub Actions runner image for ARC (Actions Runner Controller) with Azure CLI and additional tools pre-installed.

## Building

From the repository root:

```bash
docker build -t <acr-name>.azurecr.io/actions-runner:latest -f infra/github-runner/Dockerfile.runner .
```

Or locally for testing:

```bash
docker build -t actions-runner:local -f infra/github-runner/Dockerfile.runner .
```

## Publishing to Azure Container Registry

After building, push to ACR:

```bash
# Login to ACR
az acr login -n <acr-name>

# Push the image
docker push <acr-name>.azurecr.io/actions-runner:latest
```

## Using with ARC

In `infra/terraform.tfvars`, set the image URI to your ACR registry:

```hcl
arc_runner_image = "<acr-name>.azurecr.io/actions-runner:latest"
```

Then run Terraform to deploy or update ARC with the new runner image:

```bash
cd infra
terraform apply
```

Terraform will detect the change to `arc_runner_image` and re-bootstrap ARC to use the new image for runner pods.

## Image Contents

The custom runner image extends the official `ghcr.io/actions/actions-runner:latest` and adds:

- **Azure CLI** (`az`) – for Azure resource operations
- **Common build tools** – curl, gnupg, ca-certificates, lsb-release
- **apt-transport-https** – for secure package installations

## Default Image

If `arc_runner_image` is not set or uses the default value, ARC will use the official GitHub runner image from GHCR. This image includes basic tools (git, Docker, Node.js, etc.) but does NOT include Azure CLI.

## Troubleshooting

- **Image pull errors**: Ensure AKS has pull credentials for the ACR. This is configured automatically during infrastructure deployment.
- **Azure CLI not found**: Verify the custom image was successfully built and pushed, and that Terraform has applied the new image URI.
- **Workflow fails at Azure login**: Make sure you're using the custom runner image, not the default GitHub image.
