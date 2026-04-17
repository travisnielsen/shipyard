# Data Model: Azure Virtual Desktop Infrastructure

**Feature**: 002-avd-infrastructure  
**Phase**: 1 — Design  
**Date**: 2026-04-16

## Resource Entities

### AVD Host Pool (`azurerm_virtual_desktop_host_pool`)

Managed via: `Azure/avm-res-desktopvirtualization-hostpool/azurerm` v0.4.0

| Attribute | Value |
|---|---|
| name | `hp-${var.prefix}-avd` |
| type | `Pooled` |
| load_balancer_type | `BreadthFirst` |
| max_sessions_allowed | `16` |
| registration_expiry | `48h` (default) |
| start_vm_on_connect | `true` |
| Tags | `var.tags` |

**Outputs used**: `resource_id`, `registrationinfo_token`

---

### AVD Application Group (`azurerm_virtual_desktop_application_group`)

Managed via: `Azure/avm-res-desktopvirtualization-applicationgroup/azurerm` v0.2.1

| Attribute | Value |
|---|---|
| name | `ag-${var.prefix}-desktop` |
| type | `Desktop` |
| host_pool_id | `module.avd_host_pool.resource_id` |
| RBAC | `Desktop Virtualization User` → `var.avd_users_entra_group_id` |
| Tags | `var.tags` |

---

### AVD Workspace (`azurerm_virtual_desktop_workspace`)

Managed via: `Azure/avm-res-desktopvirtualization-workspace/azurerm` v0.2.2

| Attribute | Value |
|---|---|
| name | `ws-${var.prefix}-avd` |
| public_network_access_enabled | `true` (justified exception — see research.md) |
| application_group_associations | `module.avd_application_group.resource_id` |
| Tags | `var.tags` |

**Outputs used**: `resource.workspace_url` (feed URL for end users)

---

### Session Host VM (`azurerm_windows_virtual_machine`)

Managed via: `Azure/avm-res-compute-virtualmachine/azurerm` v0.20.0

| Attribute | Value |
|---|---|
| name | `vm-${var.prefix}-avd-sh0` |
| sku_size | `Standard_D2s_v5` (2 vCPUs, 8 GB RAM) |
| os_type | `Windows` |
| source_image publisher | `MicrosoftWindowsDesktop` |
| source_image offer | `windows-11` |
| source_image sku | `win11-25h2-avd` |
| source_image version | `latest` |
| os_disk caching | `ReadWrite` |
| os_disk storage_account_type | `Standard_LRS` (cost-optimised for demo) |
| subnet | `module.networking.subnets["vdi_integration"].resource_id` |
| public IP | none |
| managed_identities | `{ system_assigned = true }` |
| account_credentials | auto-generated password stored in `module.avd_keyvault` |
| zone | `null` (not required for demo, avoids zone constraint) |
| Tags | `var.tags` |

**VM Extensions** (in deploy sequence order):

| Seq | Name | Publisher | Type | Purpose |
|---|---|---|---|---|
| 1 | `AADLoginForWindows` | `Microsoft.Azure.ActiveDirectory` | `AADLoginForWindows` | Entra ID join |
| 2 | `AVDToolsInstall` | `Microsoft.Compute` | `CustomScriptExtension` | VS Code, Azure CLI, AVD agent + bootloader |

---

### Key Vault for AVD Admin Credentials (`azurerm_key_vault`)

Managed via: `Azure/avm-res-keyvault-vault/azurerm` (existing module pattern in repo)  
**Note**: Created as a simple `azurerm_key_vault` native resource scoped under the `deploy_avd` flag. The VM AVM module writes the generated admin password secret automatically when `key_vault_configuration` is set.

| Attribute | Value |
|---|---|
| name | `kv-${var.prefix}-avd-${local.identifier}` |
| sku | `standard` |
| soft_delete_retention_days | `7` |
| purge_protection_enabled | `false` (demo: allow clean destroy) |
| Tags | `var.tags` |

**Access Policy**: The deploying principal (Terraform executor) requires `Key Vault Administrator` or `Key Vault Secrets Officer` RBAC on this vault to allow the VM AVM module to write the password secret.

---

## Networking Relationships

```text
VNet (10.70.0.0/16)
└── snet-${prefix}-vdi (10.70.4.0/24)         ← vdi_integration subnet
    ├── vm-${prefix}-avd-sh0 (session host)   ← private IP only, no public IP
    └── nat-${prefix}-vm (NAT gateway)        ← shared with aks_nodes, acr_tasks, dev_vm
                                               ← must be associated to vdi_integration subnet
```

**Change to `infra/main.tf`**: Add `nat_gateway` association to `vdi_integration` subnet block (conditional on `var.enable_nat_gateway`).

---

## Resource Dependency Graph

```text
azurerm_resource_group.this
  └── module.networking
        └── vdi_integration subnet
              └── module.avd_session_host (VM)
                    ├── extension: AADLoginForWindows
                    └── extension: AVDToolsInstall
                          └── requires: module.avd_host_pool.registrationinfo_token

module.avd_host_pool (Host Pool)
  └── module.avd_application_group (App Group)
        ├── role_assignment: Desktop Virtualization User → var.avd_users_entra_group_id
        └── azurerm_virtual_desktop_workspace_application_group_association
              └── module.avd_workspace (Workspace)

azurerm_key_vault.avd (Key Vault)
  └── module.avd_session_host: account_credentials.key_vault_configuration
```

---

## Terraform Feature Flag

All AVD resources are wrapped with `count = var.deploy_avd ? 1 : 0` (or `for_each` where count is not appropriate). Disabling `deploy_avd` cleanly removes all AVD resources on the next `terraform apply`.

**Variables introduced** (see `infra/avd_variables.tf`):

| Variable | Type | Default | Description |
|---|---|---|---|
| `deploy_avd` | `bool` | `false` | Feature flag: provision all AVD resources |
| `avd_users_entra_group_id` | `string` | `""` | Object ID of the Entra ID group to assign `Desktop Virtualization User` |
| `avd_session_host_count` | `number` | `1` | Number of session host VMs to provision |
| `avd_session_host_sku` | `string` | `"Standard_D2s_v5"` | Session host VM SKU (must have ≥ 8 GB RAM) |
