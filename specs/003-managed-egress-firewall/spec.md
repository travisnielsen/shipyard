# Feature Specification: Managed Egress Firewall

**Feature Branch**: `003-managed-egress-firewall`  
**Created**: 2026-04-22  
**Status**: Draft  
**Input**: User description: "create a new feature specification for managed egress via Azure Firewall. This feature should be mutually exclusive to the existing Azure NAT Gateway approach, so if \"Managed Egress\" is turned on, Azure NAT Gateway is not deployed (or existing deployment is removed). If \"Managed Egress\" is not enabled, Azure NAT Gateway with the current subnet links needs to be in-place to support outbound traffic. Azure Firewall should be deployed in a separate VNET that is peered to the one used for the main Shipyard infrastructure (replicating the enterprise \"hub and spoke\") networking pattern. All outbound access should be alllow-listed by default, but there must be a capability to filter outbound using DNS names. This might be important when selecting the Azure Firewall SKU"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Select Egress Mode Safely (Priority: P1)

As a platform operator, I can choose a single egress mode for Shipyard environments so outbound connectivity is always available while avoiding conflicting network paths.

**Why this priority**: Outbound access is a foundational dependency for cluster operations, image pulls, package downloads, and service integration. Conflicting NAT and firewall paths can cause outages or policy bypass risk.

**Independent Test**: Can be fully tested by switching the egress mode configuration between "Managed Egress" and "NAT Gateway" in isolated test environments and verifying only the selected mode is active while outbound traffic continues.

**Acceptance Scenarios**:

1. **Given** an environment currently using NAT Gateway, **When** Managed Egress is enabled and changes are applied, **Then** NAT Gateway resources and subnet associations are removed or excluded and outbound traffic routes through managed egress.
2. **Given** an environment where Managed Egress is disabled, **When** the environment is deployed or updated, **Then** NAT Gateway and required subnet links are present and operational for outbound traffic.
3. **Given** a configuration that attempts to enable both Managed Egress and NAT Gateway simultaneously, **When** validation runs, **Then** deployment is blocked with a clear conflict error.

---

### User Story 2 - Apply Enterprise Hub-and-Spoke Pattern (Priority: P2)

As a network/security team member, I can place managed egress controls in a separate hub virtual network that is peered to Shipyard spoke networks so the environment aligns with enterprise network segmentation practices.

**Why this priority**: Enterprise adoption depends on separation of concerns and centralized security boundaries; hub-and-spoke alignment is often required by governance policies.

**Independent Test**: Can be fully tested by deploying with Managed Egress enabled and confirming a distinct egress virtual network exists, peering is established, and spoke outbound flows reach external destinations through the hub path.

**Acceptance Scenarios**:

1. **Given** Managed Egress is enabled, **When** networking is provisioned, **Then** a dedicated egress virtual network is created and peered with the Shipyard virtual network.
2. **Given** peering is in place, **When** workloads initiate outbound traffic, **Then** traffic can traverse from spoke to hub for egress processing.
3. **Given** Managed Egress is disabled, **When** deployment runs, **Then** the dedicated egress virtual network is not required for outbound connectivity.

---

### User Story 3 - Enforce Domain-Based Outbound Controls (Priority: P3)

As a security operator, I can define an explicit outbound allow-list and apply DNS-name-based filtering so only approved external destinations are reachable.

**Why this priority**: Least-privilege outbound policy reduces data exfiltration and supply-chain risk, and DNS-based controls are needed for SaaS and API endpoints that change IP addresses.

**Independent Test**: Can be fully tested by applying a policy with approved DNS destinations, verifying approved destinations are reachable, and verifying unapproved destinations are blocked with auditable events.

**Acceptance Scenarios**:

1. **Given** Managed Egress with outbound policy enabled, **When** a workload accesses an allow-listed DNS destination, **Then** the request succeeds.
2. **Given** Managed Egress with outbound policy enabled, **When** a workload accesses a non-allow-listed DNS destination, **Then** the request is denied.
3. **Given** outbound policy updates are applied, **When** policy processing completes, **Then** changes take effect without requiring full environment redeployment.

### Edge Cases

- What happens when Managed Egress is enabled for an existing environment that already has active NAT Gateway subnet associations?
- How does the system handle outbound policy rules that reference malformed or duplicate DNS names?
- What happens when policy updates would block platform-critical destinations required for baseline operations?
- How does the system behave if virtual network peering cannot be established or becomes disconnected after deployment?
- What happens when Managed Egress is disabled after previously being enabled and firewall-specific resources contain custom rule configuration?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST expose a single egress mode selection that supports exactly one of: Managed Egress or NAT Gateway.
- **FR-002**: System MUST prevent configurations that would activate Managed Egress and NAT Gateway at the same time.
- **FR-003**: When Managed Egress is enabled, system MUST ensure NAT Gateway resources and subnet associations used for Shipyard outbound traffic are absent after apply.
- **FR-004**: When Managed Egress is disabled, system MUST ensure NAT Gateway and its current required subnet links are present and configured for outbound traffic.
- **FR-005**: When Managed Egress is enabled, system MUST provision egress controls in a dedicated virtual network separate from the primary Shipyard virtual network.
- **FR-006**: System MUST establish and maintain virtual network peering between the dedicated egress virtual network and the primary Shipyard virtual network when Managed Egress is enabled.
- **FR-007**: System MUST route Shipyard outbound traffic through managed egress controls when Managed Egress is enabled.
- **FR-008**: System MUST support outbound allow-list policy management such that only explicitly approved destinations are permitted.
- **FR-009**: System MUST support outbound filtering rules based on DNS names.
- **FR-010**: System MUST provide validation feedback when selected managed egress capabilities are incompatible with the selected firewall SKU. DNS/FQDN filtering is supported on both Standard and Premium SKUs; TLS inspection or threat intelligence rules require Premium.
- **FR-011**: System MUST support safe transitions between egress modes for existing environments, including removal of obsolete resources from the previously selected mode.
- **FR-012**: System MUST preserve outbound connectivity for platform-critical dependencies during mode transitions unless explicitly overridden by operator policy.
- **FR-013**: System MUST emit deployment-time and policy-change audit events sufficient to determine whether outbound access was allowed or denied and why.
- **FR-014**: System MUST document required operator inputs for outbound allow-list and DNS filter management, including defaults.

### Key Entities *(include if feature involves data)*

- **Egress Mode Configuration**: Defines which outbound strategy is active for an environment (Managed Egress or NAT Gateway), transition intent, and validation status.
- **Egress Network Topology**: Represents the primary Shipyard virtual network, dedicated egress virtual network, and peering relationships required for traffic flow.
- **Outbound Policy Rule Set**: Represents outbound allow-list entries, DNS-name-based filters, policy priority, and effective status.
- **Mode Transition Record**: Captures a requested change from one egress mode to the other, required resource actions, and completion state.
- **Audit Event**: Captures decision outcomes for deployment checks and outbound policy enforcement (allow/deny and reason).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of deployment attempts that select an egress mode result in exactly one active outbound mode after completion.
- **SC-002**: In at least 95% of successful environment updates, switching between egress modes completes without operator rollback.
- **SC-003**: After Managed Egress policy is applied, 100% of tested non-allow-listed DNS destinations are blocked and 100% of tested allow-listed destinations remain reachable.
- **SC-004**: For production-like validation runs, no critical outbound dependency outage exceeds 5 minutes during planned egress mode transitions.
- **SC-005**: 100% of blocked outbound attempts include an auditable reason tied to the active policy rule set.

## Assumptions

- Existing Shipyard environments currently rely on NAT Gateway subnet links for baseline outbound connectivity.
- A dedicated egress virtual network can be introduced without requiring redesign of existing application-level network segmentation.
- Security/governance stakeholders will provide and maintain approved outbound destination lists.
- Environment operators need a deterministic default that keeps outbound connectivity available when Managed Egress is not enabled.
- SKU selection and cost trade-offs are handled by operators, but the system must enforce compatibility with required capabilities such as DNS-based filtering.
