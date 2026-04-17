# Research: Azure Virtual Desktop Infrastructure

**Feature**: 002-avd-infrastructure  
**Phase**: 0 — Outline & Research  
**Date**: 2026-04-16

## AVM Module Availability

**Decision**: Use Azure Verified Modules (AVM) for all AVD control-plane resources and the session host VM.  
**Rationale**: AVM modules are the project standard. All four required AVD AVM modules are published and actively maintained. Using them ensures consistent defaults, private endpoint support, role assignment integration, and diagnostic settings coverage.  
**Alternatives considered**: Native `azurerm_virtual_desktop_*` resources — rejected because AVM wrappers add lock, RBAC, diagnostics, and private endpoint interfaces out of the box.

| Purpose | AVM Module | Version |
|---|---|---|
| Host Pool | `Azure/avm-res-desktopvirtualization-hostpool/azurerm` | `0.4.0` |
| Application Group | `Azure/avm-res-desktopvirtualization-applicationgroup/azurerm` | `0.2.1` |
| Workspace | `Azure/avm-res-desktopvirtualization-workspace/azurerm` | `0.2.2` |
| Session Host VM | `Azure/avm-res-compute-virtualmachine/azurerm` | `0.20.0` |

## Terraform Version Constraint

**Decision**: Bump `infra/versions.tf` minimum Terraform version from `>= 1.9.0` to `>= 1.10.0` and add `tls ~> 4.0` provider.  
**Rationale**: `avm-res-compute-virtualmachine` v0.20.0 requires `terraform >= 1.10, < 2.0` and depends on the `tls` provider (`~> 4.0`) for auto-generated SSH/password key material. The other three AVD AVM modules are compatible with `>= 1.9`.  
**Alternatives considered**: Pinning the VM AVM module to an earlier version — rejected because older versions lack the consolidated `account_credentials` interface required for Key Vault password storage and have known breaking-change notices.

## Windows 11 Session Host Image

**Decision**: Use `MicrosoftWindowsDesktop / windows-11 / win11-25h2-avd / latest` (Windows 11 25H2 multi-session, AVD-optimized gallery image).  
**Rationale**: Direct Azure CLI SKU validation in `centralus` confirms `win11-25h2-avd` is available. Using 25H2 keeps the demo on the newest broadly available Windows 11 AVD multi-session image while retaining the `-avd` optimizations (FSLogix and AVD integration).  
**Alternatives considered**: `win11-25h2-ent` (single-session enterprise) — rejected because it only allows one concurrent user, which contradicts a pooled deployment; GPU-optimized SKUs (for example, future `-g2` variants) — rejected as out of scope per spec.

## Session Host VM SKU

**Decision**: `Standard_D2s_v5` (2 vCPUs, 8 GB RAM, Premium SSD supported, no burstable throttle).  
**Rationale**: Meets the 8 GB RAM constraint from the spec clarification; v5 generation is cost-competitive and reliably available in Central US. Premium SSD support (`Standard_SSD_LRS` or `Premium_LRS`) is needed for the OS disk.  
**Alternatives considered**: `Standard_B2ms` (burstable, 2 vCPUs, 8 GB) — rejected because burstable VMs can throttle under sustained interactive desktop workloads, producing poor user experience.

## Entra ID Join (Domain Join Method)

**Decision**: Use the `AADLoginForWindows` VM extension (publisher: `Microsoft.Azure.ActiveDirectory`, type: `AADLoginForWindows`) to Entra ID–join the session host. No Active Directory domain join required.  
**Rationale**: The spec explicitly requires Entra ID join only (FR-008). This extension enrolls the VM into Entra ID so users can authenticate with their Entra ID UPN/password or MFA. It is the standard Microsoft-documented approach for AVD personal and pooled desktops without on-premises AD.  
**Alternatives considered**: Hybrid Entra ID join (requires AD DS) — rejected, no on-premises AD in scope; Entra Domain Services (Azure AD DS) — rejected, unnecessary complexity for a demo environment.

## AVD Agent Registration

**Decision**: Install the AVD agent (RDAgent) and boot loader via a Custom Script Extension that receives the host pool registration token as a protected setting.  
**Rationale**: The host pool AVM module outputs `registrationinfo_token`. Passing this as a `protected_settings` value in the Custom Script Extension ensures the token is encrypted and not stored in state in plaintext. This is the standard community-validated pattern for Terraform-based AVD deployments.  
**Alternatives considered**: DSC extension with RDInfra configuration — rejected, more complex and poorly maintained in Terraform context; Packer-built custom images — rejected, out of scope for v1 per the spec assumption about VM extension-based tool installation.

## Tool Installation (VS Code + Azure CLI)

**Decision**: Inline PowerShell script embedded as a base64-encoded Custom Script Extension. The script downloads and silently installs VS Code (system-level, all users) and the Azure CLI MSI from their official public URLs.  
**Rationale**: No custom image pipeline is required; the session host's outbound internet access (via NAT gateway) makes direct download viable. Inline embedding avoids a dependency on a Storage Account for script hosting.  
**Script actions**:
1. Download VS Code System Installer from `https://update.code.visualstudio.com/latest/win32-x64/stable`
2. Install VS Code silently with `/VERYSILENT /NORESTART /MERGETASKS=!runcode`
3. Download Azure CLI MSI from `https://aka.ms/installazurecliwindows`
4. Install Azure CLI silently with `msiexec /I ... /quiet`
5. Install AVD RDAgent using the registration token
6. Install AVD BootLoader (Geneva Monitoring Agent)

**Alternatives considered**: Winget — rejected, requires user context; Storage Account–hosted script — rejected, adds a new storage dependency.

## Outbound Internet for Session Host

**Decision**: Associate the existing `workload` NAT gateway with the `vdi_integration` subnet by updating the `networking` module block in `infra/main.tf`.  
**Rationale**: The `vdi_integration` subnet currently has no outbound path defined. Session host VMs need outbound internet to: (1) reach AVD control plane service URLs during registration, (2) download VS Code and Azure CLI during provisioning, (3) communicate with Entra ID for user authentication. The existing NAT gateway (`nat-${var.prefix}-vm`) is already provisioned and supports additional subnet associations.  
**Alternatives considered**: Default Azure SNAT (deprecated for new VMs) — rejected, Microsoft is removing default outbound; separate NAT gateway for AVD — rejected, unnecessary duplication per the Simplicity principle.

## AVD Management Plane Network Access — Justified Exception

**Decision**: The AVD Workspace and Host Pool resources will have public network access enabled (the default). A private endpoint for the AVD management plane is NOT included in v1.  
**Rationale**: AVD user connections always traverse the Microsoft-managed AVD gateway (RD Gateway) over HTTPS. Disabling public network access on the workspace/host pool would require deploying a private endpoint into the VNet so that clients can resolve the workspace feed, which adds significant complexity (private DNS, private endpoint, client-side VPN or ExpressRoute). For a demo environment, this complexity is not justified. Session host VMs themselves have no public IP addresses and accept no inbound connections from the internet — all RDP traffic is proxied through the AVD gateway service. **This exception must be documented in the feature spec.**  
**Constitution Principle II Impact**: Partial exception — the AVD management plane (control plane) uses Microsoft-managed public endpoints; the session host compute layer is fully private.

## Key Vault for Admin Credentials

**Decision**: Create a new Azure Key Vault (`kv-${var.prefix}-avd`) scoped to the AVD deployment, using the VM AVM module's `account_credentials.key_vault_configuration` to store the generated admin password.  
**Rationale**: The constitution requires secrets in Key Vault. The VM AVM module natively supports generating a password and writing it to a specified Key Vault. A new, dedicated Key Vault keeps AVD credentials separate from any future shared Key Vault; it can be managed by the `deploy_avd` flag.  
**Alternatives considered**: Use an existing shared Key Vault — possible but would create a dependency on infra not yet defined in scope; hardcode password — explicitly forbidden by the constitution.

## RBAC — User Access to Application Group

**Decision**: Grant `Desktop Virtualization User` role on the AVD Application Group to an Entra ID group (variable `var.avd_users_entra_group_id`), using the `role_assignments` input on the `avm-res-desktopvirtualization-applicationgroup` module.  
**Rationale**: This is the documented Microsoft approach for AVD access control. Assigning to an Entra ID group (rather than individual users) satisfies Least-Privilege and is easily auditable.
