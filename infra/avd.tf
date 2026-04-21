locals {
  avd_host_pool_name         = "hp-${var.prefix}-avd"
  avd_application_group_name = "ag-${var.prefix}-desktop"
  avd_workspace_name         = "ws-${var.prefix}-avd"
  avd_key_vault_name         = lower(substr("${replace(var.prefix, "-", "")}${local.identifier}avdkv", 0, 24))
  avd_password_script_path   = "${path.module}/scripts/provision-avd-admin-password.sh"
  avd_password_script_hash   = filesha256(local.avd_password_script_path)

  avd_session_hosts = var.deploy_avd ? {
    for i in range(var.avd_session_host_count) : format("%02d", i) => i
  } : {}

  avd_tools_install_script = <<-POWERSHELL
    param(
      [Parameter(Mandatory = $true)]
      [string]$RegistrationToken
    )

    $ErrorActionPreference = "Stop"

    $ProgressPreference  = "SilentlyContinue"

    function Download-File {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$OutFile,
        [int]$TimeoutSec = 120,
        [int]$Retries = 3
      )

      for ($i = 1; $i -le $Retries; $i++) {
        try {
          Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing
          return
        }
        catch {
          if ($i -eq $Retries) {
            throw "Download failed after $Retries attempts for $Uri. $($_.Exception.Message)"
          }
          Start-Sleep -Seconds (5 * $i)
        }
      }
    }

    function Test-VSCodeInstall {
      param(
        [Parameter(Mandatory = $true)]
        [string]$InstallRoot
      )

      if (-not (Test-Path (Join-Path $InstallRoot "Code.exe"))) {
        return $false
      }

      $mainJs = Get-ChildItem -Path $InstallRoot -Filter "main.js" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*resources\\app\\out\\main.js" } |
        Select-Object -First 1

      return $null -ne $mainJs
    }

    function Install-VSCode {
      param(
        [Parameter(Mandatory = $true)]
        [string]$InstallRoot,
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath
      )

      $codeProcesses = Get-Process -Name "Code" -ErrorAction SilentlyContinue
      if ($codeProcesses) {
        $codeProcesses | Stop-Process -Force
      }

      if (Test-Path $InstallRoot) {
        Remove-Item -Path $InstallRoot -Recurse -Force
      }

      New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
      Download-File -Uri "https://update.code.visualstudio.com/latest/win32-x64-archive/stable" -OutFile $ArchivePath
      Expand-Archive -Path $ArchivePath -DestinationPath $InstallRoot -Force
      Remove-Item -Path $ArchivePath -Force -ErrorAction SilentlyContinue

      if (-not (Test-VSCodeInstall -InstallRoot $InstallRoot)) {
        throw "VS Code installation is incomplete after reinstall."
      }
    }

    $toolsRoot           = "C:\\ProgramData\\Shipyard\\bin"
    $vsCodeArchive       = "C:\\Windows\\Temp\\vscode.zip"
    $vsCodeInstallRoot   = "C:\\Program Files\\Microsoft VS Code"
    $vsCodeBinDir        = Join-Path $vsCodeInstallRoot "bin"
    $kubectlDir          = Join-Path $toolsRoot "kubectl"
    $kubectlVersion      = Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable-1.34.txt"
    $kubectlExe          = Join-Path $kubectlDir "kubectl.exe"
    $kubeloginDir        = Join-Path $toolsRoot "kubelogin"
    $kubeloginZip        = "C:\\Windows\\Temp\\kubelogin.zip"
    $rdAgentInstaller    = "C:\\Windows\\Temp\\avd-rdagent.msi"
    $bootLoaderInstaller = "C:\\Windows\\Temp\\avd-bootloader.msi"

    New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $kubectlDir -Force | Out-Null
    New-Item -ItemType Directory -Path $kubeloginDir -Force | Out-Null

    # Repair partially installed VS Code builds before continuing with the rest of bootstrap.
    if (-not (Test-VSCodeInstall -InstallRoot $vsCodeInstallRoot)) {
      Install-VSCode -InstallRoot $vsCodeInstallRoot -ArchivePath $vsCodeArchive
    }

    if (-not (Test-Path $kubectlExe)) {
      Download-File -Uri "https://dl.k8s.io/release/$kubectlVersion/bin/windows/amd64/kubectl.exe" -OutFile $kubectlExe
    }

    $kubeloginExe = Join-Path $kubeloginDir "kubelogin.exe"
    if (-not (Test-Path $kubeloginExe)) {
      Download-File -Uri "https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-win-amd64.zip" -OutFile $kubeloginZip
      Expand-Archive -Path $kubeloginZip -DestinationPath $kubeloginDir -Force
      $nested = Join-Path $kubeloginDir "bin\\windows_amd64\\kubelogin.exe"
      if (Test-Path $nested) {
        Move-Item -Path $nested -Destination $kubeloginExe -Force
      }
      Remove-Item -Path $kubeloginZip -Force -ErrorAction SilentlyContinue
    }

    # Put kubectl and kubelogin in VS Code's existing bin directory so the Kubernetes extension
    # can resolve them from the PATH it inherits when launching Code.
    Copy-Item -Path $kubectlExe -Destination (Join-Path $vsCodeBinDir "kubectl.exe") -Force
    Copy-Item -Path $kubeloginExe -Destination (Join-Path $vsCodeBinDir "kubelogin.exe") -Force

    # Add kubectl and kubelogin to system PATH
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $additions   = @($toolsRoot, $kubectlDir, $kubeloginDir, $vsCodeBinDir) | Where-Object { ($machinePath -split ';') -notcontains $_ }
    if ($additions) {
      [System.Environment]::SetEnvironmentVariable("Path", ($machinePath + ";" + ($additions -join ";")), "Machine")
    }

    $rdAgentService = Get-Service -Name "RDAgent" -ErrorAction SilentlyContinue
    $bootLoaderService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    if ($null -eq $rdAgentService -or $null -eq $bootLoaderService) {
      Download-File -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" -OutFile $rdAgentInstaller
      Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$rdAgentInstaller`" /qn /norestart REGISTRATIONTOKEN=$RegistrationToken" -Wait

      Download-File -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" -OutFile $bootLoaderInstaller
      Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$bootLoaderInstaller`" /qn /norestart" -Wait
    }

    Remove-Item -Path $vsCodeArchive, $rdAgentInstaller, $bootLoaderInstaller -Force -ErrorAction SilentlyContinue
  POWERSHELL

  avd_tools_install_script_b64 = base64encode(local.avd_tools_install_script)
}

resource "random_password" "avd_admin_password" {
  count = var.deploy_avd ? 1 : 0

  length           = 22
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  special          = true
  override_special = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
}

module "avd_key_vault" {
  count = var.deploy_avd ? 1 : 0

  source           = "Azure/avm-res-keyvault-vault/azurerm"
  version          = "0.10.2"
  enable_telemetry = false

  name                = local.avd_key_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  public_network_access_enabled = false
  network_acls = {
    bypass         = "None"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      subnet_resource_id            = module.networking.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [module.private_dns_keyvault.resource_id]
    }
  }

  tags = var.tags

  depends_on = [module.private_dns_keyvault]
}

resource "terraform_data" "avd_admin_password_secret" {
  count = var.deploy_avd ? 1 : 0

  triggers_replace = [
    module.avd_key_vault[0].resource_id,
    local.avd_password_script_hash,
    tostring(var.avd_session_host_count),
    random_password.avd_admin_password[0].result,
  ]

  provisioner "local-exec" {
    command = local.avd_password_script_path
    environment = {
      AVD_KEY_VAULT_NAME      = module.avd_key_vault[0].name
      AVD_RESOURCE_GROUP_NAME = azurerm_resource_group.this.name
      AVD_SESSION_HOST_COUNT  = tostring(var.avd_session_host_count)
      AVD_ADMIN_PASSWORD      = random_password.avd_admin_password[0].result
    }
  }

  depends_on = [
    module.avd_key_vault,
    azurerm_role_assignment.avd_keyvault_secrets_officer,
  ]
}

module "avd_host_pool" {
  count = var.deploy_avd ? 1 : 0

  source  = "Azure/avm-res-desktopvirtualization-hostpool/azurerm"
  version = "0.4.0"

  resource_group_name                           = azurerm_resource_group.this.name
  virtual_desktop_host_pool_name                = local.avd_host_pool_name
  virtual_desktop_host_pool_location            = var.location
  virtual_desktop_host_pool_resource_group_name = azurerm_resource_group.this.name
  virtual_desktop_host_pool_type                = "Pooled"
  virtual_desktop_host_pool_load_balancer_type  = "BreadthFirst"
  enable_telemetry                              = false

  registration_expiration_period                     = "48h"
  virtual_desktop_host_pool_maximum_sessions_allowed = 16
  virtual_desktop_host_pool_start_vm_on_connect      = true
  virtual_desktop_host_pool_custom_rdp_properties = {
    custom_properties = {
      # Azure persists this string with a trailing semicolon; include it to avoid serialization drift.
      targetisaadjoined = "i:1;"
      enablerdsaadauth  = "i:1"
    }
  }
  virtual_desktop_host_pool_tags = var.tags
  tags                           = var.tags
}

module "avd_application_group" {
  count = var.deploy_avd ? 1 : 0

  source           = "Azure/avm-res-desktopvirtualization-applicationgroup/azurerm"
  version          = "0.2.1"
  enable_telemetry = false

  virtual_desktop_application_group_name                = local.avd_application_group_name
  virtual_desktop_application_group_location            = var.location
  virtual_desktop_application_group_resource_group_name = azurerm_resource_group.this.name
  virtual_desktop_application_group_type                = "Desktop"
  virtual_desktop_application_group_host_pool_id        = module.avd_host_pool[0].resource_id

  role_assignments = {
    avd_users = {
      principal_id               = var.avd_users_entra_group_id
      principal_type             = "Group"
      role_definition_id_or_name = "Desktop Virtualization User"
      description                = "AVD user access scoped to desktop application group"
    }
  }

  virtual_desktop_application_group_tags = var.tags
}

module "avd_workspace" {
  count = var.deploy_avd ? 1 : 0

  source           = "Azure/avm-res-desktopvirtualization-workspace/azurerm"
  version          = "0.2.2"
  enable_telemetry = false

  virtual_desktop_workspace_name                = local.avd_workspace_name
  virtual_desktop_workspace_location            = var.location
  virtual_desktop_workspace_resource_group_name = azurerm_resource_group.this.name
  public_network_access_enabled                 = true
  virtual_desktop_workspace_tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "avd" {
  count = var.deploy_avd ? 1 : 0

  workspace_id         = module.avd_workspace[0].resource.id
  application_group_id = module.avd_application_group[0].resource.id
}

module "avd_session_host" {
  for_each = local.avd_session_hosts

  source           = "Azure/avm-res-compute-virtualmachine/azurerm"
  version          = "0.20.0"
  enable_telemetry = false

  name                = "vm${substr(var.prefix, 0, 3)}avdsh${each.key}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  zone                = null

  sku_size = var.avd_session_host_sku
  os_type  = "Windows"

  account_credentials = {
    admin_credentials = {
      username                           = "azureuser"
      password                           = random_password.avd_admin_password[0].result
      generate_admin_password_or_ssh_key = false
    }
  }

  source_image_reference = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-25h2-avd"
    version   = "latest"
  }

  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  managed_identities = {
    system_assigned = true
  }

  encryption_at_host_enabled = false

  network_interfaces = {
    primary = {
      name = "nic${substr(var.prefix, 0, 3)}avdsh${each.key}"
      ip_configurations = {
        primary = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = module.networking.subnets["vdi_integration"].resource_id
        }
      }
    }
  }

  extensions = {
    aad_login = {
      name                 = "AADLoginForWindows"
      publisher            = "Microsoft.Azure.ActiveDirectory"
      type                 = "AADLoginForWindows"
      type_handler_version = "2.1"
      deploy_sequence      = 1
      settings             = jsonencode({ mdmId = "" })
      tags                 = var.tags
    }

    avd_tools_install = {
      name                 = "AVDToolsInstall"
      publisher            = "Microsoft.Compute"
      type                 = "CustomScriptExtension"
      type_handler_version = "1.10"
      deploy_sequence      = 2
      settings             = jsonencode({ timestamp = 1 })
      protected_settings = jsonencode({
        commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"[IO.File]::WriteAllText('C:\\\\Windows\\\\Temp\\\\avd-bootstrap.ps1',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${local.avd_tools_install_script_b64}'))); & 'C:\\\\Windows\\\\Temp\\\\avd-bootstrap.ps1' -RegistrationToken '${module.avd_host_pool[0].registrationinfo_token}'\""
      })
      tags = var.tags
    }
  }

  tags = var.tags

  depends_on = [
    module.avd_host_pool,
    azurerm_virtual_desktop_workspace_application_group_association.avd,
    terraform_data.avd_admin_password_secret,
  ]
}
