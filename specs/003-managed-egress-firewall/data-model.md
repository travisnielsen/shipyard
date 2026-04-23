# Data Model: Managed Egress via Azure Firewall

**Feature**: 003-managed-egress-firewall  
**Phase**: 1 — Design  
**Date**: 2026-04-22

## Configuration Entities

### Egress Mode Configuration

Defines active outbound strategy and transition expectations.

| Attribute | Type | Rules |
|---|---|---|
| managed_egress_enabled | boolean | When true, NAT gateway mode must be disabled |
| enable_nat_gateway | boolean | Must be true when managed_egress_enabled is false for default Shipyard outbound path |
| mode_effective | enum(`managed_firewall`, `nat_gateway`) | Derived from flags; exactly one value |
| validation_state | enum(`valid`, `invalid`) | Invalid when mutual exclusivity or required-input rules fail |
| transition_state | enum(`none`, `to_managed`, `to_nat`) | Derived from prior vs target state during apply |

### Egress Hub Network Topology

Represents the dedicated managed-egress hub.

| Attribute | Type | Rules |
|---|---|---|
| hub_vnet_cidr | string (CIDR) | Must not overlap with Shipyard spoke VNet |
| hub_firewall_subnet_cidr | string (CIDR) | Must be named `AzureFirewallSubnet` and meet Azure size requirements |
| hub_to_spoke_peering_state | enum(`connected`, `disconnected`) | Must be `connected` when managed egress enabled |
| spoke_to_hub_peering_state | enum(`connected`, `disconnected`) | Must be `connected` when managed egress enabled |

### Outbound Routing Attachment

Captures route steering from Shipyard subnets to firewall.

| Attribute | Type | Rules |
|---|---|---|
| target_subnet_key | enum(`aks_nodes`, `acr_tasks`, `vdi_integration`, `dev_vm`) | Only outbound-capable spoke subnets |
| route_table_attached | boolean | Must be true for targeted subnets when managed egress enabled |
| default_route_next_hop | string (IP) | Must match firewall private IP when managed egress enabled |
| route_effective | boolean | True only when UDR association is applied successfully |

### Outbound Policy Rule Set

Defines explicit outbound allow-list and DNS-based controls.

| Attribute | Type | Rules |
|---|---|---|
| firewall_sku | enum(`Standard`, `Premium`) | Must be compatible with requested capabilities. Standard: DNS/FQDN filtering, basic allow/deny rules. Premium: TLS inspection, threat intelligence, advanced log analytics. |
| default_action | enum(`Deny`) | Managed egress baseline must be deny-by-default |
| allow_fqdns | list(string) | FQDN entries must be valid DNS names and unique |
| allow_network_destinations | list(object) | Optional explicit IP/CIDR destinations for non-FQDN flows |
| policy_version | string | Updated on each policy change |
| policy_effective_state | enum(`pending`, `applied`, `failed`) | Tracks rollout state for auditability |

### Audit Event

Records mode and policy enforcement outcomes.

| Attribute | Type | Rules |
|---|---|---|
| event_type | enum(`mode_validation`, `mode_transition`, `policy_allow`, `policy_deny`) | Required |
| event_timestamp | datetime | Required |
| subject | string | Deployment operation or workload identity |
| decision | enum(`allow`, `deny`, `pass`, `fail`) | Required |
| reason_code | string | Required for deny/fail outcomes |
| correlation_id | string | Used to group apply/policy operations |

## Relationships

- One Egress Mode Configuration governs one effective outbound mode.
- Managed mode requires one Egress Hub Network Topology.
- Managed mode requires many Outbound Routing Attachments (per spoke subnet).
- Managed mode uses one Outbound Policy Rule Set with many destination rules.
- Each transition and policy decision produces many Audit Events.

## State Transitions

### Mode Transition

1. `nat_gateway` -> `managed_firewall`
- Validate mutual exclusivity and required managed-egress inputs.
- Provision hub VNet, firewall subnet, firewall resources, and peering.
- Attach route tables in spoke subnets to firewall next hop.
- Remove NAT gateway resources and subnet associations.
- Mark mode effective as `managed_firewall`.

2. `managed_firewall` -> `nat_gateway`
- Validate NAT requirements for current spoke subnets.
- Recreate/attach NAT gateway to required subnets.
- Remove managed-egress routing and hub firewall resources (or disable if retained by policy).
- Mark mode effective as `nat_gateway`.

## Validation Rules

- `managed_egress_enabled = true` implies `enable_nat_gateway = false`.
- `managed_egress_enabled = false` implies `enable_nat_gateway = true` for default outbound support.
- Managed egress requires non-overlapping hub VNet CIDR and valid peering configuration.
- Managed egress requires explicit allow-list entries for required platform dependencies before apply completes.
- FQDN rule entries must be syntactically valid and duplicate-free.
- SKU/feature combinations must pass validation before resource creation.
