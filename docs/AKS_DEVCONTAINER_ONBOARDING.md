# AKS DevContainer Onboarding Guide

This guide is for end users and developers who need to connect VS Code to the shared AKS environment and attach to their remote development container.

## Prerequisites

- You have a working VDI session.
- `kubectl` and `kubelogin` are installed on the machine.
- The platform operator has provided your Kubernetes config file and your assigned namespace.

## 1) Enable Required VS Code Extensions

Open VS Code and install/enable these extensions:

- **Dev Containers** (`ms-vscode-remote.remote-containers`)
- **Kubernetes** (`ms-kubernetes-tools.vscode-kubernetes-tools`)

Verification:

1. Open Command Palette (`Ctrl+Shift+P`).
2. Type `Dev Containers` and confirm commands appear (for example: `Dev Containers: Attach to Running Kubernetes Container...`).
3. Type `Kubernetes` and confirm Kubernetes commands appear.

## 2) Place the Kubernetes Config File

Get the kubeconfig file from the operator and save it to your user kube directory.

### Windows (VDI)

1. Ensure this folder exists:
   - `C:\Users\<your-user>\.kube`
2. Save the file as:
   - `C:\Users\<your-user>\.kube\config`

### Optional check

Run:

```powershell
kubectl config current-context
```

You should see your AKS context name.

## 3) Authenticate to AKS (Device Code or Interactive Browser)

Your environment supports both flows.

### Option A: Device Code

```powershell
kubelogin convert-kubeconfig -l devicecode
kubectl get ns
```

Follow the prompt to open the Microsoft device login page and enter the code.

### Option B: Interactive Browser

```powershell
kubelogin convert-kubeconfig -l interactive
kubectl get ns
```

This opens a browser sign-in flow directly.

### Notes

- You only need to run `convert-kubeconfig` again when changing login mode.
- If auth cache becomes stale, clear tokens and retry:

```powershell
kubelogin remove-tokens
kubectl get ns
```

## 4) Switch to Your Assigned Namespace

Set your default namespace for the current context:

```powershell
kubectl config set-context --current --namespace <your-assigned-namespace>
```

Verify it:

```powershell
kubectl config view --minify --output "jsonpath={..namespace}"
```

Also verify access:

```powershell
kubectl get pods
```

## 5) Connect to the Remote Dev Container

Use the Command Palette flow shown in your screenshot.

1. Open Command Palette (`Ctrl+Shift+P`).
2. Run: `Dev Containers: Attach to Running Kubernetes Container...`
3. Select your AKS context.
4. Select your assigned namespace.
5. Select the target pod.
6. Select the container.
7. When prompted for a folder, choose the project/workspace directory inside the container.

VS Code opens a new remote window attached to that running container.

## Quick Validation Checklist

- `kubectl config current-context` returns expected AKS context.
- `kubectl get ns` succeeds after sign-in.
- Default namespace is set to your assigned namespace.
- `Dev Containers: Attach to Running Kubernetes Container...` connects successfully.

## Troubleshooting

- **"kubelogin is not installed"**: Confirm `kubelogin.exe` is on PATH and restart VS Code.
- **Unauthorized/forbidden errors**: Confirm with operator that your Entra identity has AKS RBAC access and namespace permissions.
- **Cannot find pod in attach flow**: Verify correct context and namespace, then run `kubectl get pods -n <your-assigned-namespace>`.
- **Browser auth popup blocked**: Use `devicecode` login mode instead.
