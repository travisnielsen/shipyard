# Managed Egress Topology

This document describes the managed egress path for the Shipyard greenfield deployment when `managed_egress_enabled = true` and `enable_nat_gateway = false`.

In this mode, outbound traffic from developer workloads is forced through a dedicated Azure Firewall deployed in a separate hub virtual network. The spoke virtual network hosts the Shipyard AKS cluster and related workload subnets. Hub-and-spoke peering plus user-defined routes ensure outbound traffic is inspected and filtered before it leaves the private network.

## Topology Summary

- The Shipyard spoke VNet continues to host AKS, ACR task, VDI integration, and utility VM subnets.
- A dedicated egress hub VNet contains `AzureFirewallSubnet` and the Azure Firewall instance.
- Bidirectional VNet peering connects the spoke and hub VNets.
- User-defined routes on outbound-capable spoke subnets send `0.0.0.0/0` to the firewall private IP.
- Azure Firewall Policy applies a default-deny posture with explicit FQDN and optional IP/CIDR allow-lists.
- Platform-critical destinations such as `management.azure.com`, `login.microsoftonline.com`, and `mcr.microsoft.com` are preserved in the effective allow-list.

## Managed Egress Diagram

```mermaid
graph TB
    subgraph VDI["🖥️ VDI Environment"]
        Developer["📝 VS Code<br/>Dev Containers Ext."]
    end

    subgraph Spoke["☸️ Shipyard Spoke VNet"]
        AKSApi["🔑 AKS API Server<br/>Port 6443/TCP"]
        AKSNodes["💻 AKS Node Subnet<br/>aks_nodes"]
        Workloads["🐳 Dev Workspace Pods<br/>build/test/debug"]
        ACRTasks["📦 ACR Tasks Subnet<br/>acr_tasks"]
        VDIIntegration["🧭 VDI Integration Subnet<br/>vdi_integration"]
        DevVM["🛠️ Utility / Dev VM Subnet<br/>dev_vm"]
        RouteTable["🛣️ UDR Default Route<br/>0.0.0.0/0 -> Firewall IP"]
    end

    subgraph Hub["🛡️ Managed Egress Hub VNet"]
        Peering["🔗 VNet Peering<br/>spoke <-> hub"]
        FirewallSubnet["📍 AzureFirewallSubnet"]
        Firewall["🔥 Azure Firewall<br/>Standard or Premium"]
        Policy["📋 Firewall Policy<br/>default deny + allow-list"]
        PublicIP["🌐 Firewall Public IP<br/>egress only"]
    end

    subgraph Services["☁️ Approved Azure / Internet Destinations"]
        ARM["⚙️ Azure Resource Manager<br/>management.azure.com"]
        Entra["🔐 Microsoft Entra ID<br/>login.microsoftonline.com"]
        MCR["📦 Microsoft Container Registry<br/>mcr.microsoft.com"]
        Approved["✅ Approved External FQDNs / IPs"]
        Denied["⛔ Non-Allow-Listed Destinations"]
    end

    subgraph Network["🔒 Private Routing & DNS"]
        DNS["Port 53/UDP<br/>private DNS + name resolution"]
    end

    Developer -->|port-forward| AKSApi
    AKSApi -->|kubelet| AKSNodes
    AKSNodes -->|schedules| Workloads
    ACRTasks --> RouteTable
    VDIIntegration --> RouteTable
    DevVM --> RouteTable
    AKSNodes --> RouteTable
    RouteTable -->|next hop| Firewall
    Peering --> FirewallSubnet
    FirewallSubnet --> Firewall
    Firewall --> Policy
    Firewall -->|443| ARM
    Firewall -->|443| Entra
    Firewall -->|443| MCR
    Firewall -->|allowed| Approved
    Firewall -. blocked .-> Denied
    Firewall -->|SNAT| PublicIP
    AKSApi -.->|DNS| DNS
    Firewall -.->|DNS| DNS
    ARM -.->|DNS| DNS
    Entra -.->|DNS| DNS
    MCR -.->|DNS| DNS

    classDef vdiStyle fill:#1a237e,stroke:#64b5f6,stroke-width:2px,color:#fff
    classDef aksStyle fill:#311b92,stroke:#ce93d8,stroke-width:2px,color:#fff
    classDef serviceStyle fill:#3e2723,stroke:#ffb74d,stroke-width:2px,color:#fff
    classDef networkStyle fill:#0d3b0d,stroke:#81c784,stroke-width:2px,color:#fff

    class VDI vdiStyle
    class Spoke,AKSApi,AKSNodes,Workloads,ACRTasks,VDIIntegration,DevVM,RouteTable aksStyle
    class Hub,Peering,FirewallSubnet,Firewall,Policy,PublicIP serviceStyle
    class Services,ARM,Entra,MCR,Approved,Denied,Network,DNS networkStyle
```

## Traffic Flow

1. A developer connects from the VDI environment to a remote workspace running in AKS.
2. Workload traffic leaves the outbound-capable spoke subnet.
3. The subnet route table sends the default route to the firewall private IP in the hub.
4. Azure Firewall evaluates the request against the attached firewall policy.
5. Allowed traffic is SNATed through the firewall public IP and sent to approved destinations.
6. Non-allow-listed destinations are denied and can be observed through firewall diagnostics.

## Subnets Routed Through Managed Egress

- `aks_nodes`
- `acr_tasks`
- `vdi_integration`
- `dev_vm`

These are the same outbound-capable subnets updated by the managed egress route table associations in [infra/networking.tf](../infra/networking.tf).

## Policy Model

- Default action: deny outbound traffic unless a rule explicitly allows it.
- FQDN allow-list: application rules for approved DNS destinations.
- Optional IP/CIDR allow-list: network rules for endpoints that cannot be expressed as FQDNs.
- Platform dependency preservation: required Azure control-plane and image registry destinations are merged into the effective allow-list.

## When To Use Managed Egress

Use managed egress when you need one or more of the following:

- Centralized outbound inspection for AKS-hosted developer workloads.
- Deny-by-default control of external dependencies.
- A hub-and-spoke network pattern that cleanly separates workload hosting from egress enforcement.
- A transition path away from broad NAT-based outbound access.

For operator steps and transition guidance, see [DEPLOYMENT_RUNBOOK.md](./DEPLOYMENT_RUNBOOK.md).
