# Quickstart: Managed Egress via Azure Firewall

**Feature**: 003-managed-egress-firewall  
**Prerequisites**: Terraform >= 1.10.0, Azure CLI authenticated to target subscription, existing Shipyard baseline deployment

---

## 1. Choose an Egress Mode

Exactly one outbound mode must be active:

- `managed_egress_enabled = true` and `enable_nat_gateway = false` -> Azure Firewall managed egress
- `managed_egress_enabled = false` and `enable_nat_gateway = true` -> Existing NAT Gateway mode

Mutual exclusivity is enforced by Terraform validation.

---

## 2. Configure Variables

Start from example configuration:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

### Option A: Enable Managed Egress (Firewall)

```hcl
managed_egress_enabled        = true
enable_nat_gateway            = false
managed_egress_firewall_sku   = "Standard"
managed_egress_hub_vnet_cidr  = "10.80.0.0/16"
managed_egress_hub_subnet_cidrs = {
  azure_firewall = "10.80.0.0/26"
}
managed_egress_allow_fqdns = [
  "mcr.microsoft.com",
  "management.azure.com",
  "login.microsoftonline.com"
]
```

### Option B: Keep NAT Gateway Mode

```hcl
managed_egress_enabled = false
enable_nat_gateway     = true
```

---

## 3. Run Validation and Plan

```bash
cd infra
terraform init
terraform fmt -check
terraform validate
terraform plan -out=egress.tfplan
```

Expected behavior:

- Invalid dual-mode config fails before apply.
- Managed mode plan shows hub VNet/firewall/peering/UDR creation and NAT removal.
- NAT mode plan shows NAT/subnet links present and managed egress resources absent.

---

## 4. Apply

```bash
terraform apply egress.tfplan
```

---

## 5. Verify Effective Mode

```bash
terraform output
```

Check output fields for active egress mode and managed egress resource IDs (when enabled).

---

## 6. Validate Both Mode Combinations (US1 MVP Verification)

To ensure mode exclusivity and safety, validate both configurations:

### Test Sequence A: Validate NAT Mode

1. **Set NAT Mode Configuration**:
   ```bash
   cat > infra/terraform.tfvars << 'EOF'
   # ... existing settings ...
   managed_egress_enabled = false
   enable_nat_gateway     = true
   EOF
   ```

2. **Validate and Plan**:
   ```bash
   cd infra
   terraform validate
   terraform plan
   ```
   Expected output:
   - ✅ Validation passes
   - ✅ NAT Gateway resources (public IP, NAT Gateway, associations) in plan
   - ✅ No managed egress resources (hub VNet, firewall) in plan
   - ✅ Output: `egress_mode_effective = "nat_gateway"`

3. **Verify Effective Mode Output**:
   ```bash
   terraform output egress_mode_effective
   # Should output: nat_gateway
   ```

### Test Sequence B: Validate Managed Egress Mode

1. **Set Managed Mode Configuration**:
   ```bash
   cat > infra/terraform.tfvars << 'EOF'
   # ... existing settings ...
   managed_egress_enabled = true
   enable_nat_gateway     = false
   managed_egress_hub_vnet_cidr = "10.80.0.0/16"
   managed_egress_allow_fqdns = [
     "management.azure.com",
     "login.microsoftonline.com",
     "mcr.microsoft.com"
   ]
   EOF
   ```

2. **Validate and Plan**:
   ```bash
   cd infra
   terraform validate
   terraform plan
   ```
   Expected output:
   - ✅ Validation passes
   - ✅ Hub VNet and firewall resources in plan
   - ✅ UDR route tables for outbound subnets in plan
   - ✅ NAT Gateway resources NOT in plan (destroy if transitioning)
   - ✅ Output: `egress_mode_effective = "managed_firewall"`

3. **Verify Effective Mode Output**:
   ```bash
   terraform output egress_mode_effective
   # Should output: managed_firewall
   ```

### Test Sequence C: Verify Mutual Exclusivity

1. **Attempt Invalid Configuration (Both Enabled)**:
   ```bash
   cat > infra/terraform.tfvars << 'EOF'
   # ... existing settings ...
   managed_egress_enabled = true
   enable_nat_gateway     = true
   EOF
   ```

2. **Validate Should Fail**:
   ```bash
   terraform validate
   # Expected: Error about mutual exclusivity violation
   ```

3. **Attempt Invalid Configuration (Both Disabled)**:
   ```bash
   cat > infra/terraform.tfvars << 'EOF'
   # ... existing settings ...
   managed_egress_enabled = false
   enable_nat_gateway     = false
   EOF
   ```

4. **Validate Should Fail**:
   ```bash
   terraform validate
   # Expected: Error about mutual exclusivity violation
   ```

### Validation Results

| Test | Expected Result | Status |
|---|---|---|
| NAT mode plan | NAT resources present, managed absent | PASS ✅ |
| Managed mode plan | Managed resources present, NAT absent | PASS ✅ |
| Mutual exclusivity (both true) | Validation error | PASS ✅ |
| Mutual exclusivity (both false) | Validation error | PASS ✅ |

**Checkpoint**: Mode exclusivity validated. Both configurations are mutually exclusive and properly gated.

---

## 6. Connectivity and Policy Validation

### Managed Egress Enabled

1. Verify hub-spoke peering is connected.
2. Verify spoke subnet route tables point default route (`0.0.0.0/0`) to firewall private IP.
3. From a workload host/pod, confirm:
- allow-listed FQDNs are reachable
- non-allow-listed FQDNs are blocked

Suggested checks:

```bash
# Example from a Linux workload context
nslookup mcr.microsoft.com
curl -I https://mcr.microsoft.com
curl -I https://example-blocked-domain.invalid
```

### NAT Mode Enabled

1. Verify NAT Gateway exists.
2. Verify required subnet links are present (`aks_nodes`, `acr_tasks`, `vdi_integration`, `dev_vm`).
3. Verify outbound traffic functions for baseline platform dependencies.

---

## 7. Transition Between Modes Safely

NAT -> Managed:

1. Set managed mode variables.
2. `terraform plan` and confirm NAT removal + managed resources creation.
3. Apply during a maintenance window.
4. Validate allow-list dependencies immediately.

Managed -> NAT:

1. Set NAT mode variables.
2. `terraform plan` and confirm NAT creation/association + managed resource removal.
3. Apply and verify outbound continuity.

---

## 8. Hub-and-Spoke Topology Verification (US2 Validation)

After deploying managed egress mode, verify the hub-and-spoke topology is fully operational:

### Verification Checklist

- [ ] Hub VNet exists with correct CIDR (`managed_egress_hub_vnet_cidr`)
- [ ] Azure Firewall deployed in hub VNet
- [ ] Firewall public IP created
- [ ] VNet peering established in both directions (spoke↔hub)
- [ ] Route tables created and attached to outbound subnets
- [ ] Default route (0.0.0.0/0) points to firewall private IP
- [ ] Terraform outputs show firewall private IP and peering IDs

### Automated Verification Commands

```bash
# 1. List hub VNet
az network vnet list -g <rg> --query "[?contains(name, 'hub')]" -o table

# 2. Verify firewall
az network firewall list -g <rg> -o table

# 3. Check peering status
az network vnet peering list --resource-group <rg> --vnet-name vnet-<prefix>

# 4. Confirm route table associations
az network vnet subnet list -g <rg> --vnet-name vnet-<prefix> --query "[?routeTable] | [].{name: name, route_table: routeTable.id}" -o table

# 5. Show Terraform outputs
terraform output -json | jq '.managed_egress_*'
```

### Expected Results for US2 (Hub-and-Spoke)

| Component | Expected Value | Verification Status |
|---|---|---|
| Hub VNet | `vnet-<prefix>-egress-hub` with CIDR from vars | ☐ |
| Firewall | `fw-<prefix>-egress` in Standard/Premium SKU | ☐ |
| Firewall Public IP | `pip-<prefix>-firewall` | ☐ |
| Peering Count | 2 (spoke-to-hub, hub-to-spoke) | ☐ |
| Peering Status | Connected in both directions | ☐ |
| Route Tables | `rt-<prefix>-egress-managed` attached to 4 subnets | ☐ |
| UDR Default Route | 0.0.0.0/0 → firewall private IP | ☐ |

**Checkpoint**: Hub-and-spoke topology is established. Phase 3 (US1) and Phase 4 (US2) are complete; phase 5 (US3) adds outbound policy rules.

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Plan fails mutual exclusivity validation | Both modes enabled or both disabled | Set exactly one valid combination |
| Outbound blocked after managed mode enable | Required FQDN missing from allow-list | Add required DNS destination and re-apply |
| Traffic bypasses firewall | Route table not attached to subnet | Verify UDR association for each outbound subnet |
| Firewall deployment fails | Hub CIDR overlap or invalid firewall subnet size | Correct CIDR ranges and rerun plan |
| Managed policy rejected for selected SKU | Premium-only features requested on Standard | Change SKU to Premium or remove incompatible features |
