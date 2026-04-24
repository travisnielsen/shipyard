# Research: Managed Egress via Azure Firewall

**Feature**: 003-managed-egress-firewall  
**Phase**: 0 — Outline & Research  
**Date**: 2026-04-22

## Decision 1: Egress Mode Control Model

**Decision**: Introduce a new feature flag `managed_egress_enabled` and enforce mutual exclusivity with existing `enable_nat_gateway` using Terraform validation logic.

**Rationale**: The repo already uses feature flags for infrastructure toggles. Explicit validation prevents invalid dual-mode configurations and makes transitions deterministic for brownfield updates.

**Alternatives considered**:
- Implicit behavior (auto-disable NAT when managed egress is enabled): rejected because implicit mutation hides operator intent and can surprise pipelines.
- Single enum variable only (replace `enable_nat_gateway`): rejected for v1 because it is more disruptive to existing variable contracts and examples.

## Decision 2: Firewall Placement and Topology

**Decision**: Deploy Azure Firewall in a dedicated hub VNet and peer it with the existing Shipyard spoke VNet; keep workload subnets in the existing VNet.

**Rationale**: This matches enterprise hub-and-spoke architecture, maintains current subnet ownership in `networking.tf`, and localizes managed egress controls to a separate egress boundary.

**Alternatives considered**:
- Deploy firewall directly in existing Shipyard VNet: rejected because it does not satisfy the requested hub-and-spoke separation.
- Use Azure Virtual WAN secured hub: rejected for this feature due to additional platform complexity and broader operational blast radius.

## Decision 3: Routing Strategy for Managed Egress

**Decision**: When managed egress is enabled, create and associate route tables for outbound-capable spoke subnets with `0.0.0.0/0` next hop set to Azure Firewall private IP.

**Rationale**: UDR-based egress steering is deterministic and required to ensure outbound traffic traverses firewall policy enforcement rather than default internet/NAT paths.

**Alternatives considered**:
- Rely only on firewall rules without UDR changes: rejected because traffic would bypass firewall.
- Per-workload custom routes outside Terraform: rejected due to IaC-first governance requirements.

## Decision 4: Azure Firewall SKU for DNS/FQDN Filtering

**Decision**: Support `Standard` and `Premium` SKUs, defaulting to `Standard`; require SKU-policy compatibility checks for any premium-only features.

**Rationale**: DNS/FQDN filtering and application rule allow-list controls are supported in standard enterprise patterns with Azure Firewall Standard. Premium remains available for environments that need TLS inspection/advanced threat signatures.

**Alternatives considered**:
- Premium-only: rejected because it forces higher cost for use cases that only require FQDN allow-listing.
- Standard-only: rejected because some tenants will require premium controls later.

## Decision 5: Outbound Policy Model

**Decision**: Enforce default-deny posture for managed egress and require explicit allow-list rules (including DNS-name based destinations) for outbound access.

**Rationale**: The feature requirement states outbound access should be allow-listed by default. Default deny with explicit allow-list satisfies least-privilege and auditability goals.

**Alternatives considered**:
- Allow-all baseline with optional deny rules: rejected because it contradicts the requested default allow-list model.
- IP-only filtering: rejected because SaaS/API dependencies often use dynamic IPs and require DNS-name controls.

## Decision 6: NAT Gateway Behavior by Mode

**Decision**:
- If `managed_egress_enabled = true`, ensure NAT gateway resources and subnet links are absent.
- If `managed_egress_enabled = false`, keep existing NAT gateway behavior and current subnet links in place.

**Rationale**: This directly enforces FR-003 and FR-004 and preserves backward compatibility for existing Shipyard deployments.

**Alternatives considered**:
- Keep NAT attached while also steering to firewall: rejected because it violates mutual exclusivity and complicates operational intent.

## Decision 7: Terraform and Module Pattern

**Decision**: Keep all egress-networking resources in `infra/networking.tf` (network domain file) and use Azure Verified Modules where available; keep any role assignments in `infra/rbac.tf` if needed.

**Rationale**: Repository conventions explicitly place VNet fabric and egress controls in `networking.tf` and centralize RBAC in `rbac.tf`.

**Alternatives considered**:
- New standalone `firewall.tf`: rejected for now because this feature remains part of network fabric and egress controls already owned by `networking.tf`.

## Decision 8: Validation and Rollout Safety

**Decision**: Require pre-apply validation that identifies mode conflicts, incompatible SKU/feature combinations, and missing required allow-list inputs when managed egress is enabled.

**Rationale**: Early validation reduces runtime drift and prevents lockout events during egress transitions.

**Alternatives considered**:
- Post-deploy checks only: rejected because failures would occur too late and increase outage risk.
