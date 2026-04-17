# Quickstart: Azure Virtual Desktop

**Feature**: 002-avd-infrastructure  
**Prerequisites**: Terraform >= 1.10.0, Azure CLI, an Azure subscription, Entra ID group Object ID for AVD users

---

## 1. Create an Entra ID Group for AVD Users

```bash
# Create a group (or use an existing one)
az ad group create --display-name "AVD Users" --mail-nickname "avd-users"

# Get the group Object ID — you will need this for terraform.tfvars
az ad group show --group "AVD Users" --query id -o tsv
```

---

## 2. Update terraform.tfvars

Copy the example file and set the required values:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

Add or update these keys in `infra/terraform.tfvars`:

```hcl
deploy_avd                  = true
avd_users_entra_group_id    = "<paste-group-object-id-here>"
# Optional overrides (defaults are demo-appropriate):
# avd_session_host_count    = 1
# avd_session_host_sku      = "Standard_D2s_v5"
```

---

## 3. Deploy

```bash
cd infra

terraform init
terraform plan -out=avd.tfplan
terraform apply avd.tfplan
```

Deployment takes approximately 15–25 minutes (VM provisioning + extensions).

---

## 4. Connect to the Desktop

After `terraform apply` completes, retrieve the workspace URL:

```bash
terraform output avd_workspace_url
```

**Option A — Web Client (no install required)**:

1. Open a browser and go to `https://client.wvd.microsoft.com/arm/webclient/`
2. Sign in with an Entra ID account that is a member of your AVD Users group
3. Click the **Desktop** tile and wait for the session to start

**Option B — Windows Desktop Client**:

1. [Download the Windows Desktop Client](https://go.microsoft.com/fwlink/?linkid=2068602)
2. Open the client → **Subscribe with URL** → paste the workspace URL from `terraform output avd_workspace_url`
3. Sign in with your Entra ID account
4. Double-click the **Desktop** resource to connect

---

## 5. Verify Tools

Once connected to the Windows 11 desktop:

```powershell
# Verify Azure CLI
az --version

# Launch VS Code from Start menu or run:
code .
```

Both should work without any additional installation.

Post-restart validation:

```bash
# Start or restart the first session host if needed
az vm restart -g <resource-group> -n vm-<prefix>-avd-sh00
```

Reconnect to AVD and verify both `az --version` and `code .` still work.

---

## 6. Validate User Access Controls

Authorized user test:

1. Ensure the user is a member of the group configured in `avd_users_entra_group_id`.
2. Sign in to the AVD web client and connect to Desktop.
3. Record successful access result and timestamp.

Unauthorized user test:

1. Use a same-tenant Entra ID user that is not in the AVD users group.
2. Attempt to subscribe/connect to the same workspace.
3. Record denied access result.

SC-005 evidence template (fill after test run):

```text
Unauthorized access attempts: <N>
Denied attempts: <N>
Pass criteria: denied == attempts (100%)
```

---

## 7. Retrieve the Admin Password (for Bastion access)

The session host admin password is stored in the AVD Key Vault. To retrieve it:

```bash
KV_NAME=$(terraform output -raw avd_keyvault_name)
az keyvault secret list --vault-name "$KV_NAME" --query "[].name" -o tsv
az keyvault secret show --vault-name "$KV_NAME" --name "<secret-name>" --query value -o tsv
```

---

## 8. Terraform Idempotency and Tear Down

Validate idempotency:

```bash
terraform plan
```

Expected result: no unintended changes when configuration is already applied.

Tear down AVD only:

To remove all AVD resources without affecting the rest of the infrastructure:

```bash
# In terraform.tfvars, set:
#   deploy_avd = false

terraform apply -var="deploy_avd=false"
```

This cleanly removes the session host VM, host pool, application group, workspace, and Key Vault.

---

## 9. Measure SC-001 Connection Latency

Measure connect time from pressing **Connect** in the client until desktop interactivity:

1. Start a timer when clicking **Connect**.
2. Stop timer when desktop is interactive (Start menu responds).
3. Repeat at least 3 times and record results.

Evidence template:

```text
Run 1: <seconds>
Run 2: <seconds>
Run 3: <seconds>
Average: <seconds>
Pass criteria: each run < 180 seconds
```

---

## 10. Verify SC-006 Network Posture

Verify session hosts have no public IP and no inbound internet exposure:

```bash
az vm list-ip-addresses -g <resource-group> -n vm-<prefix>-avd-sh00 -o json
az network nic show -g <resource-group> -n nic-<prefix>-avd-sh00 --query "ipConfigurations[].publicIpAddress" -o json
```

Expected result: no public IP assigned.

Verify management path is Bastion or private network only:

```bash
az network bastion show -g <resource-group> -n bas-<prefix>-workload --query "name" -o tsv
```

Evidence template:

```text
Session host public IP: none
Inbound exposure check: pass
Management path: Bastion/private only
```

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| "No resources available" in AVD client | Session host not registered | Wait 10 min after `apply`; check VM extension status in portal |
| Extension `AVDToolsInstall` fails | Outbound internet blocked | Confirm NAT gateway is associated with `vdi_integration` subnet |
| Extension `AVDToolsInstall` fails with download/install errors | Endpoint blocked by firewall/proxy | Confirm outbound HTTPS to Microsoft download endpoints and retry extension |
| User cannot connect (access denied) | Not in AVD Users group | Add user to the Entra ID group used for `avd_users_entra_group_id` |
| Blank screen after connecting | VM deallocated | Start the VM: `az vm start -g <rg> -n vm-<prefix>-avd-sh0` |
| `az` not found in session | Script extension failed | Re-run extension or redeploy session host |
