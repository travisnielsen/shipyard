# Feature Specification: Azure Virtual Desktop Infrastructure

**Feature Branch**: `002-avd-infrastructure`  
**Created**: 2026-04-16  
**Status**: Draft  
**Input**: User description: "Create a new feature that adds Azure Virtual Desktop (AVD) to the infrastructure. Users should be able to sign-in and work in a basic Windows 11 desktop with VS Code installed. The desktop should also include the Azure CLI. The compute infrastructure should fit into the existing network defined in Terraform."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Access a Windows 11 Desktop via AVD (Priority: P1)

As a developer or platform engineer, I can sign in with my Entra ID account and connect to a Windows 11 session desktop so I have a ready-to-use cloud workstation without managing local infrastructure.

**Why this priority**: This is the core capability of the feature — delivering a functional AVD desktop session is the primary user-facing outcome. All other stories depend on this foundation.

**Independent Test**: Can be fully tested by an authorized user signing in via the AVD web client or Windows Desktop client, establishing a desktop session, and confirming a Windows 11 desktop is presented.

**Acceptance Scenarios**:

1. **Given** an authorized Entra ID user is assigned to the AVD application group, **When** they open the AVD client and connect, **Then** they are presented with a full Windows 11 desktop session.
2. **Given** an unauthorized user, **When** they attempt to connect, **Then** access is denied and no session is started.
3. **Given** an active session, **When** the user disconnects and reconnects within the session lifetime, **Then** the session and any open work are preserved.

---

### User Story 2 - Use VS Code and Azure CLI from the Desktop (Priority: P2)

As a developer, I can launch VS Code and use the Azure CLI from within the AVD session so I can write code and interact with Azure resources immediately without additional setup.

**Why this priority**: Pre-installed tooling is the stated requirement and differentiates this cloud workstation from a bare desktop. It delivers immediate developer productivity.

**Independent Test**: Can be fully tested independently by connecting to a session, launching VS Code from the Start menu, and running `az --version` in a terminal — both must succeed without any user-initiated installation.

**Acceptance Scenarios**:

1. **Given** an active Windows 11 desktop session, **When** the user launches VS Code, **Then** VS Code opens and is functional.
2. **Given** an active Windows 11 desktop session, **When** the user opens a terminal and runs `az --version`, **Then** the Azure CLI version is displayed successfully.
3. **Given** a session host that has been restarted, **When** a user connects, **Then** VS Code and Azure CLI are still present without reinstallation.

---

### User Story 3 - Provision and Manage AVD Infrastructure via Terraform (Priority: P3)

As a platform maintainer, I can apply Terraform to provision or update the AVD infrastructure so all AVD resources are managed consistently alongside existing shipyard infrastructure.

**Why this priority**: Infrastructure-as-code consistency is a project principle. Platform maintainers must be able to reproduce or update AVD without manual portal steps.

**Independent Test**: Can be fully tested by running `terraform apply` from scratch (or against an existing state) and confirming all AVD resources are created/updated without error.

**Acceptance Scenarios**:

1. **Given** a clean environment with the existing VNet and resource group, **When** a platform maintainer runs `terraform apply` with AVD variables set, **Then** all AVD resources (host pool, application group, workspace, session host VM) are created successfully.
2. **Given** existing AVD resources in state, **When** a maintainer runs `terraform plan`, **Then** no unintended changes are shown for already-correct resources.
3. **Given** AVD is deployed, **When** a maintainer sets `deploy_avd = false` and applies, **Then** AVD resources are cleanly removed without affecting shared networking or other resources.

---

### Edge Cases

- What happens when a session host VM is deallocated? Users attempting to connect should receive a clear error; re-starting the VM via the portal or automation should restore availability.
- What happens if Entra ID group assignment is removed from a user who has an active session? The current session continues until the session ends; new connection attempts are denied.
- What happens if the `vdi_integration` subnet CIDR is exhausted? Terraform should fail with a meaningful error rather than partially provisioning session hosts.
- How does the system handle session host image updates? Updated images require session host VM replacement — this is a known operational step and is out of scope for v1 automation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The infrastructure MUST provision an AVD host pool configured for pooled desktop sessions on the existing `vdi_integration` subnet.
- **FR-002**: AVD session host VMs MUST run Windows 11 multi-session or single-session OS with VS Code and Azure CLI pre-installed via a provisioning extension or custom script. VMs MUST use a low-cost general-purpose SKU with 8 GB RAM (e.g., `Standard_D2s_v5`: 2 vCPUs, 8 GB RAM) appropriate for a demo environment.
- **FR-003**: Users MUST authenticate to AVD using their own Entra ID account (UPN/password or MFA) from the same tenant as the AVD deployment — no local accounts or shared credentials are permitted. Authorized users are identified by membership in an Entra ID group assigned to the AVD application group.
- **FR-004**: All AVD resources MUST be provisioned within the existing resource group and virtual network defined in the shipyard Terraform configuration.
- **FR-005**: AVD session host VMs MUST be placed in the `vdi_integration` subnet (`10.70.4.0/24`) of the existing VNet.
- **FR-006**: The Terraform configuration MUST include a feature flag (`deploy_avd`) to enable or disable the AVD deployment without affecting other resources.
- **FR-007**: Access to the AVD application group MUST be controlled via Entra ID group assignment managed through Terraform or a setup script.
- **FR-008**: Session host VMs MUST be domain-joined via Entra ID (Microsoft Entra ID join) so no on-premises Active Directory is required.
- **FR-009**: All AVD infrastructure components MUST be tagged consistently using the existing `var.tags` pattern.
- **FR-010**: The deployment MUST produce an output containing the AVD workspace URL so users can locate the connection endpoint.

### Private-by-Default Networking Exception (Constitution Principle II)

This feature requires public management-plane access for Azure Virtual Desktop Workspace/Host Pool (`public_network_access_enabled = true`) so users can connect via the Microsoft-managed AVD web/desktop clients.

Scope of exception:

- Applies only to AVD control-plane endpoints.
- Session host VMs remain private (no public IP, no inbound internet exposure).

Justification:

- Private endpoint + private DNS + client VPN/ExpressRoute requirements add disproportionate complexity for this demo environment.
- Security posture is preserved through reverse-connect AVD gateway model and private session hosts.

Approval:

- This exception requires explicit PR review approval per constitution.

### Key Entities

- **Host Pool**: The AVD resource that defines session host configuration, load balancing type, and session limits. Can be pooled (shared, multiple users) or personal (dedicated per user).
- **Application Group**: Associates desktops or published apps with the host pool; controls what users see in their feed.
- **Workspace**: The AVD resource that aggregates application groups and presents a unified feed to end users.
- **Session Host VM**: The Windows 11 virtual machine registered to the host pool where user sessions run; resides in the `vdi_integration` subnet.
- **Registration Token**: A time-limited token used to join a session host VM to a host pool; must be refreshed for re-registration scenarios.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An authorized user can sign in and reach a functional Windows 11 desktop in under 3 minutes from clicking "Connect."
- **SC-002**: VS Code and the Azure CLI are immediately available after session start with zero additional user-initiated installation steps.
- **SC-003**: A platform maintainer can provision the entire AVD environment from zero using a single `terraform apply` run with no manual portal steps required.
- **SC-004**: Terraform plan and apply complete without errors on both initial provisioning and subsequent idempotent runs.
- **SC-005**: Unauthorized users are denied access — 100% of connection attempts by non-assigned users are blocked.
- **SC-006**: Session host VMs are reachable only from within the VNet (no public inbound); all management is performed via Bastion or existing access patterns.

## Clarifications

### Session 2026-04-16

- Q: What compute cost tier and RAM size should be used for session host VMs? → A: Low-cost compute, 8 GB RAM per session host (demo environment). Default SKU: `Standard_D2s_v5` (2 vCPUs, 8 GB RAM).
- Q: How should users authenticate to AVD? → A: Users sign in with their own Entra ID account from the same tenant as the AVD deployment; no local accounts or shared credentials; cross-tenant (B2B) access is out of scope.

## Assumptions

- The existing Terraform state and resource group (`rg-shipyard-dev`) will be used as the deployment target; AVD resources will be added incrementally.
- The `vdi_integration` subnet (`10.70.4.0/24`) is already defined in the Terraform network module and will be used as-is for session host VMs.
- No on-premises Active Directory is present or required; Entra ID join is the only supported domain-join method.
- A single session host VM (or small pool) is sufficient for v1; horizontal scaling is out of scope.
- Session host image customization (VS Code, Azure CLI) will be handled via a VM extension or custom script during provisioning, not a custom managed image, to keep the pipeline simple.
- Users already have Entra ID accounts in the same tenant where the AVD host pool is deployed; cross-tenant (B2B guest) access is out of scope for v1.
- The AVD desktop type is a full desktop session (not published RemoteApp); RemoteApp publishing is out of scope for v1.
- Mobile AVD client support is out of scope; supported clients are the AVD web client and Windows Desktop client.
- This is a demo environment; session host VM size is constrained to low-cost SKUs with exactly 8 GB RAM. The default SKU is `Standard_D2s_v5` (2 vCPUs, 8 GB RAM); GPU-accelerated SKUs are out of scope.
- Outbound internet access for session host VMs MUST use the existing NAT gateway associated with the `vdi_integration` subnet.
