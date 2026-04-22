# Port Requirements: VDI to AKS DevContainer Communication

This document describes the network ports and protocols required for Azure Virtual Desktop (AVD) session hosts to communicate with AKS-hosted development containers.

## Overview

The developer workflow consists of:
1. **AVD Session Host** (Windows 11 multi-session VM in `vdi_integration` subnet)
2. **VDI User** (session within AVD session host)
3. **AKS Cluster** (private cluster in `aks_nodes` subnet)
4. **DevContainer Pod** (running in AKS namespace with code-server)

Traffic flows from the VDI session host → private AKS API → devcontainer pod.

## Network Topology

```
AVD Session Host (vdi_integration: 10.70.4.0/24)
    ↓
VNet Peering / Routing
    ↓
AKS Control Plane (private, system DNS zone)
    ↓
AKS Nodes (aks_nodes: 10.70.1.0/24)
    ↓
DevContainer Pod (namespace: devcontainer-<username>)
```

## Port Matrix

| Layer | Service | Protocol | Port | Source | Destination | Purpose |
|-------|---------|----------|------|--------|-------------|---------|
| **Kubernetes API** | kube-apiserver | HTTPS | 6443 | AVD session host | AKS API server (private, system DNS zone) | kubectl commands, authentication, workload identity token exchange |
| **Code Editor** | code-server / VS Code Server | HTTPS | 8443 | AVD session host | DevContainer pod (via kubectl port-forward or direct attachment) | Remote IDE connection, code editing, debugging |
| **Container Registry** | Azure Container Registry | HTTPS | 443 | AKS nodes (kubelet) | ACR private endpoint | Image pull for devcontainer pod |
| **Storage** | Azure Files (SMB) | SMB | 445 | AKS nodes (kubelet + cluster MI) | Storage account private endpoint | Mount PersistentVolumeClaim backed by Azure Files |
| **Key Vault** | Azure Key Vault | HTTPS | 443 | AKS nodes | Key Vault private endpoint | Kubelet retrieves container registry credentials (optional CSI driver) |
| **Azure Control Plane** | Azure API | HTTPS | 443 | AKS nodes (cluster MI, kubelet MI) | Azure public API (via NAT) or private endpoints | Azure resource operations, managed identity token exchange |
| **DNS** | Azure Private DNS | DNS | 53 | All subnets | Private DNS zones | Name resolution for private endpoints (ACR, Key Vault, Storage) |

## Detailed Port Descriptions

### 1. Kubernetes API Server (Port 6443 / HTTPS)

**Flow**: VDI user's `kubectl` or VS Code extension → AKS API server

**Requirements**:
- AVD session host must have outbound HTTPS connectivity to the AKS API server private endpoint
- Private DNS zone (`privatelink.containerservice.azure.us` for US regions, region-specific for others) must resolve the AKS API server FQDN to the private IP
- Network path: `vdi_integration` subnet → VNet routing → `aks_nodes` subnet (via NAT gateway or direct peering)
- kubelogin or Azure CLI handles authentication; certificates are validated over this connection

**Validation**:
```bash
# From VDI session host, verify connectivity:
kubectl cluster-info
kubectl auth can-i list pods --namespace devcontainer-<username>
```

**Firewall/NSG Considerations**:
- AVD subnet NSG must allow outbound HTTPS (port 443) to support API calls; port 6443 is typically allowed via outbound "allow all" or explicit allow rules
- AKS subnet NSG typically allows inbound from within VNet (no cross-subnet restrictions for private AKS)
- Private AKS does not expose port 6443 on the internet; API is only accessible via private endpoint within the VNet

### 2. VS Code Remote Container (Port 8443 / HTTPS)

**Flow**: VDI user's VS Code → DevContainer pod (kubectl port-forward or direct attachment)

**Connection Methods**:

#### Method A: Dev Containers Extension Attach
- VS Code "Attach to Running Kubernetes Container" command
- Uses kubectl to access the pod; code-server runs inside the pod
- Port 8443 (container port) is forwarded via `kubectl port-forward` (local tunnel on VDI host)
- Local VS Code connects to `localhost:8443` or dynamically assigned local port

**Requirements**:
- kubectl access (covered by port 6443)
- Outbound HTTPS from pod to any external services (for extensions, language servers, debugging)
- Pod network policy must allow inbound from kubelet/host (for port-forward)

#### Method B: Code Server / Remote Tunnels (Optional)
- If using direct code-server connection or VS Code tunnels feature
- Requires outbound HTTPS (443) from pod to GitHub tunnels service or external relay
- Not currently configured in this repo; the attached container method is the standard flow

**Validation**:
```bash
# From VDI session host, verify pod is running:
kubectl get pods -n devcontainer-<username>

# Forward the port:
kubectl port-forward -n devcontainer-<username> pod/dev-workspace-xyz 8443:8443

# Then connect in VS Code:
# 1. Command Palette → Dev Containers: Attach to Running Kubernetes Container
# 2. Select pod
# 3. VS Code installs server inside pod and connects via port 8443
```

**Port Forward Path**:
- VS Code extension initiates kubectl port-forward via the API server (port 6443)
- Local VS Code client connects to `localhost:8443`
- Traffic inside pod goes to code-server listening on 8443

**Network Security**:
- Port 8443 is only exposed within the pod and the kueblet host; no external exposure
- Controlled via kubectl RBAC: user must have "portforward" permission on pods

### 3. Container Registry (Port 443 / HTTPS)

**Flow**: AKS kubelet → Azure Container Registry (pull image for devcontainer pod)

**Requirements**:
- Azure Container Registry private endpoint must be accessible from `aks_nodes` subnet
- Private DNS zone (`privatelink.azurecr.io`) resolves ACR FQDN to private IP
- Kubelet identity (or cluster managed identity) must have `AcrPull` role on ACR
- Network path: `aks_nodes` → private endpoint subnet → ACR

**Port Details**:
- Standard HTTPS port 443 for all ACR registry operations (pull, push, token exchanges)
- Private endpoint exposes ACR registry API on the private IP in the `private_endpoints` subnet

**Validation** (from AKS node or pod):
```bash
# Inside pod:
curl -v https://acr-name.azurecr.io/v2/_catalog

# Or verify via kubelet logs:
kubectl describe node <node-name>
```

**Common Issues**:
- If `imagePullBackOff` error: verify ACR private endpoint DNS resolution and network connectivity
- If authentication fails: check kubelet identity has `AcrPull` role on ACR

### 4. Azure Files / SMB (Port 445 / SMB3 with Encryption)

**Flow**: AKS kubelet + cluster managed identity → Azure Files share (mount `/workspaces` PVC)

**Requirements** (Kubernetes 1.34+):
- **Two managed identities** must have Storage RBAC roles:
  - **Kubelet managed identity** (agentpool identity): required for volume mount operations
  - **Cluster managed identity** (control-plane identity): required for share create/delete in AKS 1.34+ controllerless CSI mode
- Required roles on storage account:
  1. `Storage File Data SMB MI Admin` — for mount and access
  2. `Storage Account Contributor` — for share lifecycle
  3. `Storage File Data SMB Share Contributor` — for share-level permissions
- Storage account must have **SMB OAuth enabled**
- Azure Files CSI driver (file.csi.azure.com) must be installed and operational
- Private endpoint for storage account in `private_endpoints` subnet
- Private DNS zone (privatelink.file.core.windows.net) resolves storage account FQDN to private IP

**Port Details**:
- SMB (Server Message Block) protocol, typically port 445
- Azure Files enforces SMB3 with encryption (HTTPS equivalent security)
- All traffic is encrypted; plaintext SMB is not supported on Azure Files

**Validation** (from AKS node or in pod):
```bash
# Inside pod, verify mount:
df -h /workspaces
ls -la /workspaces

# Check CSI driver health:
kubectl get daemonset -n kube-system csi-azurefile-node

# Verify storage account connection (from node, not pod):
# This is handled by kubelet; you typically won't run SMB commands directly
```

**AKS 1.34+ Specifics**:
- `csi-azurefile-controller` Deployment does **not exist** (controllerless model)
- Controller sidecar runs in `csi-azurefile-node` DaemonSet pods
- File share provisioning happens via cluster managed identity (not just kubelet)

**Common Issues**:
- `PermissionDenied` on PVC: check both identities have Storage RBAC roles
- `MountFailure`: verify SMB OAuth enabled on storage account, private endpoint DNS resolution
- `timeout waiting for mount`: check AKS node → storage account network path, NSG rules, private endpoint

### 5. Azure Key Vault (Port 443 / HTTPS)

**Flow**: AKS kubelet → Azure Key Vault (optional: retrieve ACR credentials or secrets)

**Requirements**:
- Key Vault private endpoint in `private_endpoints` subnet
- Private DNS zone (privatelink.vaultcore.azure.net) resolves Key Vault FQDN to private IP
- Kubelet identity must have appropriate Key Vault access policies or RBAC (typically `Key Vault Secrets User`)
- Kubernetes workload identity pods can retrieve secrets if configured with appropriate RBAC

**Port Details**:
- Standard HTTPS port 443
- All operations: authentication, secret retrieval, certificate operations

**Use Cases in This Repo**:
- AVD session host credentials stored in dedicated AVD Key Vault (not accessed by AKS pods)
- Shared Key Vault contains platform secrets; ACR credentials can be retrieved by pods if needed

**Validation**:
```bash
# From AKS node or pod (if workload identity is configured):
curl -H "Authorization: Bearer $TOKEN" https://key-vault-name.vault.azure.net/secrets/my-secret?api-version=7.4
```

### 6. Azure API (Port 443 / HTTPS)

**Flow**: AKS managed identities → Azure public API or private endpoints

**Requirements**:
- AKS nodes need outbound HTTPS connectivity for:
  - Managed identity token exchange (`https://management.azure.com` for control-plane identity)
  - Azure Resource Manager API calls (if using Workload Identity)
  - Service-specific APIs (if configured)
- Network path: typically via NAT gateway for public API access, or private endpoints for service-specific APIs

**Port Details**:
- Standard HTTPS port 443
- Outbound to `*.management.azure.com`, `*.azure.com`, and region-specific service endpoints

**Validation** (from AKS node):
```bash
# Verify outbound connectivity:
curl -v https://management.azure.com

# Check NAT gateway public IP:
kubectl get nodes -o wide
```

### 7. DNS (Port 53 / UDP and TCP)

**Flow**: All nodes and pods → Azure Private DNS zones

**Requirements**:
- Private DNS zones must be linked to the VNet:
  - `privatelink.containerservice.<region>` — for AKS API server
  - `privatelink.azurecr.io` — for ACR
  - `privatelink.vaultcore.azure.net` — for Key Vault
  - `privatelink.file.core.windows.net` — for Storage
- DNS queries from pods and nodes are resolved by Azure DNS (168.63.129.16)
- Forward lookup must return private IP addresses for private endpoints

**Port Details**:
- UDP port 53 (preferred)
- TCP port 53 (fallback for large responses)
- Azure DNS is built-in; no firewall configuration needed

**Validation** (from pod or node):
```bash
# Inside pod, verify private DNS resolution:
nslookup aks-name.privatelink.containerservice.centralus.azmk8s.io

# Should resolve to private IP in aks_nodes subnet (e.g., 10.70.1.x)

# Inside pod, verify ACR resolution:
nslookup acr-name.azurecr.io

# Should resolve to private IP in private_endpoints subnet (e.g., 10.70.3.x)
```

## Network Security Group (NSG) Rules

### VDI Integration Subnet NSG (outbound to AKS)

| Direction | Protocol | Port | Source | Destination | Purpose |
|-----------|----------|------|--------|-------------|---------|
| Outbound | TCP | 6443 | vdi_integration subnet | AKS control plane IP (private) | Kubernetes API access |
| Outbound | TCP | 443 | vdi_integration subnet | ACR private endpoint IP | Image pull authentication |
| Outbound | TCP | 443 | vdi_integration subnet | Key Vault private endpoint IP | Secret/credential retrieval |
| Outbound | TCP | 445 | vdi_integration subnet | Storage private endpoint IP | SMB file mount (managed identity auth) |
| Outbound | UDP | 53 | vdi_integration subnet | Azure DNS (168.63.129.16) | Private DNS resolution |
| Outbound | TCP | 443 | vdi_integration subnet | Azure public API | Managed identity token exchange (via NAT) |

**Note**: Most of these are handled by the VNet architecture and private endpoints. Explicit NSG rules may not be required if your default NSG allows outbound traffic or if you use private link service for internal routing.

### AKS Node Subnet NSG (inbound from VDI)

| Direction | Protocol | Port | Source | Destination | Purpose |
|-----------|----------|------|--------|-------------|---------|
| Inbound | TCP | 6443 | vdi_integration subnet | AKS API server (private) | Kubernetes API access |
| Inbound | TCP | 443 | vdi_integration subnet | AKS nodes | Port-forward for code-server (via kubelet proxy) |

**Note**: AKS typically uses allow-all inbound for internal VNet traffic. Explicit rules depend on your security posture.

## Troubleshooting Port Connectivity

### Cannot reach AKS API (port 6443)

**Symptoms**: `kubectl cluster-info` fails with connection timeout

**Checklist**:
1. Verify private DNS is resolving AKS API server FQDN:
   ```powershell
   # From VDI session host (Windows):
   nslookup aks-name.privatelink.containerservice.centralus.azmk8s.io
   # Should resolve to private IP (e.g., 10.70.x.x)
   ```
2. Verify VDI subnet → AKS subnet routing exists (via VNet)
3. Check VDI subnet NSG allows outbound HTTPS (port 443 covers 6443 via TCP)
4. Confirm kubelogin is installed and authentication tokens are valid:
   ```powershell
   kubelogin convert-kubeconfig -l devicecode
   ```

### Cannot attach to container (port 8443)

**Symptoms**: VS Code attach fails or hangs; code-server connection timeout

**Checklist**:
1. Verify pod is running:
   ```bash
   kubectl get pods -n devcontainer-<username>
   # Should show 1/1 Running
   ```
2. Verify container is exposing port 8443:
   ```bash
   kubectl describe pod -n devcontainer-<username> dev-workspace-xyz | grep -A 5 "Ports:"
   # Should show containerPort: 8443
   ```
3. Test port-forward manually:
   ```bash
   kubectl port-forward -n devcontainer-<username> pod/dev-workspace-xyz 8443:8443
   # Should show: Forwarding from 127.0.0.1:8443 -> 8443
   ```
4. Check VS Code Dev Containers extension logs (Output panel: "Dev Containers")
5. Verify RBAC: user must have `pods/portforward` permission

### Cannot pull container image (ACR port 443)

**Symptoms**: Pod stuck in `ImagePullBackOff`

**Checklist**:
1. Verify ACR private endpoint DNS resolution from node:
   ```bash
   kubectl debug node/<node-name> -it --image=busybox
   nslookup acr-name.azurecr.io
   # Should resolve to private IP in private_endpoints subnet
   ```
2. Verify kubelet identity has `AcrPull` role:
   ```bash
   az role assignment list --assignee <kubelet-mi-principal-id> --scope <acr-id> --query "[?roleDefinitionName=='AcrPull']"
   ```
3. Check ACR network rules allow AKS nodes:
   ```bash
   az acr network-rule list --name <acr-name> --resource-group <rg>
   ```

### Cannot mount file share (SMB port 445)

**Symptoms**: Pod crashes or hangs on PVC mount with `PermissionDenied`, `Timeout`, or `MountFailure`

**Checklist**:
1. Verify both managed identities have Storage RBAC:
   ```bash
   # Kubelet MI:
   az role assignment list --assignee <kubelet-mi-principal-id> --scope <storage-account-id>
   
   # Cluster MI:
   az role assignment list --assignee <cluster-mi-principal-id> --scope <storage-account-id>
   ```
2. Verify SMB OAuth is enabled on storage account:
   ```bash
   az storage account show -n <storage-account-name> -g <rg> --query "azureFilesIdentityBasedAuthentication"
   # Should show "DirectoryServiceOptions": "AADKERB" or "AADFS"
   ```
3. Verify storage account private endpoint DNS:
   ```bash
   kubectl debug node/<node-name> -it --image=busybox
   nslookup <storage-account-name>.file.core.windows.net
   # Should resolve to private IP
   ```
4. Check CSI driver health (AKS 1.34+):
   ```bash
   kubectl get daemonset -n kube-system csi-azurefile-node
   kubectl logs -n kube-system -l app=csi-azurefile-node --tail 50
   ```

## Summary

**Minimum required ports from VDI to AKS**:
- **6443/TCP (HTTPS)** — Kubernetes API server (kubctl, authentication, workload identity)
- **8443/TCP (HTTPS)** — Code-server pod (VS Code remote attach, port-forward via API)
- **443/TCP (HTTPS)** — Private endpoints (ACR, Key Vault)
- **445/TCP (SMB3)** — Azure Files (persistent volume mounts)
- **53/UDP** — Private DNS zones (name resolution)

**Network flow**:
```
VDI (10.70.4.0/24)
  ├─ outbound to AKS API (10.70.1.x via private endpoint)
  ├─ outbound to ACR private endpoint (10.70.3.x)
  ├─ outbound to Storage private endpoint (10.70.3.x)
  └─ DNS queries to Azure DNS (168.63.129.16)
```

All communication is encrypted; traffic is restricted to private subnets and private endpoints. No internet routes or public IPs are required for AVD-to-AKS devcontainer workflows.
