#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Username,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$StorageResourceGroup,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$StorageAccountName,

    [Parameter(Position = 3)]
    [string]$ShareName
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ShareName)) {
    $ShareName = "devcontainer-$Username"
}

$Namespace = "devcontainer-$Username"
$StorageClassName = "devcontainer-azurefile-mi-$Username"
$ManifestsDir = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath '..' | Join-Path -ChildPath 'devcontainer' | Join-Path -ChildPath 'manifests'
$ManifestsDir = [System.IO.Path]::GetFullPath($ManifestsDir)

function Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message"
    exit 1
}

function Test-CommandAvailable {
    param([string]$CommandName)
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        Fail "Required command not found: $CommandName"
    }
}

function Invoke-AzJson {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String))) {
        return $null
    }

    return ($output | Out-String | ConvertFrom-Json)
}

function Invoke-KubectlApplyText {
    param([string]$Content)
    $Content | & kubectl apply -f -
    if ($LASTEXITCODE -ne 0) {
        Fail 'kubectl apply failed.'
    }
}

function Test-KubectlCanGet {
    param([string]$Resource)

    $canI = & kubectl auth can-i get $Resource 2>&1
    $canIText = ($canI | Out-String)

    if ($LASTEXITCODE -ne 0 -or $canIText -match '^no\b') {
        Fail "Current identity cannot get '$Resource' from the cluster. On AKS with Azure RBAC enabled, assign 'Azure Kubernetes Service RBAC Cluster Admin' (or a role that grants this resource) and refresh credentials."
    }
}

function Wait-DeploymentAvailable {
    param(
        [string]$Namespace,
        [string]$DeploymentName,
        [int]$TimeoutSeconds = 240
    )
    $result = & kubectl rollout status deployment/$DeploymentName -n $Namespace --timeout="${TimeoutSeconds}s" 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Show-WorkspaceDiagnostics {
    param(
        [string]$Namespace,
        [string]$StorageClassName
    )
    Write-Host ''
    Write-Host '--- Diagnostics ---'
    Write-Host "Pods in $Namespace :"
    & kubectl get pods -n $Namespace -o wide 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host "Events in $Namespace :"
    & kubectl get events -n $Namespace --sort-by='.lastTimestamp' 2>&1 | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
    Write-Host "PVC status in $Namespace :"
    & kubectl get pvc -n $Namespace -o wide 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host '--- End Diagnostics ---'
}

Write-Host "==> Provisioning workspace for '$Username' in namespace '$Namespace'"
Write-Host "    Storage RG      : $StorageResourceGroup"
Write-Host "    Storage account : $StorageAccountName"
Write-Host "    File share      : $ShareName"
Write-Host "    StorageClass    : $StorageClassName"
Write-Host ''

Test-CommandAvailable kubectl
Test-CommandAvailable az

$WorkspaceImage = $env:DEV_WORKSPACE_IMAGE
if ([string]::IsNullOrWhiteSpace($WorkspaceImage)) {
    $acrList = Invoke-AzJson @("acr", "list", "--resource-group", $StorageResourceGroup, "-o", "json")
    if ($null -ne $acrList -and $acrList.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace(($acrList[0].loginServer | Out-String).Trim())) {
        $WorkspaceImage = "$(($acrList[0].loginServer | Out-String).Trim())/remote-devcontainer:latest"
    }
    elseif ($null -ne $acrList -and $acrList.Count -gt 1) {
        Fail "Multiple ACR registries found in resource group '$StorageResourceGroup'. Set DEV_WORKSPACE_IMAGE explicitly (for example: '<acr-login-server>/remote-devcontainer:latest')."
    }
    else {
        Fail "Could not resolve a workspace image automatically. Set DEV_WORKSPACE_IMAGE (for example: '<acr-login-server>/remote-devcontainer:latest')."
    }
}

Write-Host "    Workspace image : $WorkspaceImage"

Write-Host '--> Running preflight validation checks...'

Write-Host "    [1/7] Checking kubectl connectivity..."
$versionJson = & kubectl version -o json 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($versionJson | Out-String))) {
    Fail "Could not detect Kubernetes server version from current kubectl context. Run 'az aks get-credentials --resource-group <aks-rg> --name <aks-name> --overwrite-existing' and retry."
}

$version = $versionJson | Out-String | ConvertFrom-Json
$serverMajor = (($version.serverVersion.major ?? '') -replace '[^0-9]', '')
$serverMinorRaw = ($version.serverVersion.minor ?? '')
$serverMinor = ($serverMinorRaw -replace '[^0-9]', '')

if ([string]::IsNullOrWhiteSpace($serverMajor) -or [string]::IsNullOrWhiteSpace($serverMinor)) {
    Fail "Could not detect Kubernetes server version from current kubectl context. Run 'az aks get-credentials --resource-group <aks-rg> --name <aks-name> --overwrite-existing' and retry."
}

Write-Host "    [2/7] Validating Kubernetes version (found $serverMajor.$serverMinorRaw)..."
if (([int]$serverMajor -lt 1) -or (([int]$serverMajor -eq 1) -and ([int]$serverMinor -lt 34))) {
    Fail "AKS Kubernetes version $serverMajor.$serverMinorRaw does not meet minimum 1.34 for Azure Files managed identity mount mode."
}

Test-KubectlCanGet 'csidrivers.storage.k8s.io'

& kubectl get csidriver file.csi.azure.com -o name *> $null
if ($LASTEXITCODE -ne 0) {
    $csiCheckOutput = (& kubectl get csidriver file.csi.azure.com -o name 2>&1 | Out-String)
    if ($csiCheckOutput -match 'forbidden|does not have access to the resource in Azure') {
        Fail "Unable to verify Azure Files CSI driver because this identity cannot access cluster-scoped CSI resources. Assign 'Azure Kubernetes Service RBAC Cluster Admin' (or equivalent) and refresh credentials."
    }

    Fail 'Azure Files CSI driver (file.csi.azure.com) is not available in the current cluster.'
}

# Dynamic Azure Files provisioning requires the controller — either as a
# standalone deployment (AKS < 1.34) or embedded in the node DaemonSet
# (AKS >= 1.34 controllerless model).
$azureFileController = & kubectl get deployment csi-azurefile-controller -n kube-system -o name 2>&1
if ($LASTEXITCODE -ne 0) {
    $controllerError = ($azureFileController | Out-String)
    if ($controllerError -match 'NotFound|not found') {
        # AKS 1.34+ uses a controllerless model where the controller
        # sidecar runs inside the csi-azurefile-node DaemonSet pods.
        $nodeDs = & kubectl get daemonset csi-azurefile-node -n kube-system -o jsonpath='{.status.numberReady}' 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($nodeDs | Out-String).Trim()) -or (($nodeDs | Out-String).Trim() -eq '0')) {
            Fail "Azure File CSI controller deployment is missing and the csi-azurefile-node DaemonSet has no ready pods. Dynamic Azure Files provisioning will not work until this AKS addon issue is resolved."
        }
        Write-Host "    [3/7] Azure File CSI controller running in node DaemonSet (controllerless mode)..."
    }
    else {
        Write-Host "WARNING: Could not verify csi-azurefile-controller deployment due to: $controllerError"
    }
}
else {
    Write-Host "    [3/7] Azure File CSI controller deployment verified..."
}

Write-Host "    [4/7] Discovering AKS cluster..."

$AksResourceGroup = $env:AKS_RESOURCE_GROUP
$AksClusterName = $env:AKS_CLUSTER_NAME
$WorkspaceImage = $env:DEV_WORKSPACE_IMAGE

if ([string]::IsNullOrWhiteSpace($AksResourceGroup) -or [string]::IsNullOrWhiteSpace($AksClusterName)) {
    $discovered = Invoke-AzJson @('aks', 'list', '-o', 'json')
    if ($null -eq $discovered -or $discovered.Count -eq 0) {
        Fail 'No AKS clusters were discovered in the current Azure context. Set AKS_RESOURCE_GROUP and AKS_CLUSTER_NAME.'
    }

    if ($discovered.Count -gt 1) {
        Write-Host 'Discovered multiple AKS clusters:'
        foreach ($cluster in $discovered) {
            Write-Host "  - $($cluster.resourceGroup)|$($cluster.name)"
        }
        Fail 'Set AKS_RESOURCE_GROUP and AKS_CLUSTER_NAME explicitly to continue.'
    }

    $AksResourceGroup = $discovered[0].resourceGroup
    $AksClusterName = $discovered[0].name
}

if ([string]::IsNullOrWhiteSpace($WorkspaceImage)) {
    $acrLoginServersRaw = & az acr list --resource-group $AksResourceGroup --query "[].loginServer" --output tsv 2>$null
    $acrLoginServers = @($acrLoginServersRaw | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })

    if ($acrLoginServers.Count -eq 1) {
        $WorkspaceImage = "$($acrLoginServers[0])/remote-devcontainer:latest"
    } elseif ($acrLoginServers.Count -gt 1) {
        Fail "Discovered multiple ACR registries in $AksResourceGroup. Set DEV_WORKSPACE_IMAGE explicitly (for example: <acr-login-server>/remote-devcontainer:latest)."
    }
}

$kubeletIdentity = Invoke-AzJson @('aks', 'show', '--resource-group', $AksResourceGroup, '--name', $AksClusterName, '--query', 'identityProfile.kubeletidentity', '-o', 'json')
$kubeletObjectId = ''
if ($null -ne $kubeletIdentity) {
    $kubeletObjectId = "$(($kubeletIdentity.objectId ?? $kubeletIdentity.object_id) ?? '')".Trim()
}
if ([string]::IsNullOrWhiteSpace($kubeletObjectId)) {
    Fail "Could not resolve AKS kubelet identity object ID for $AksResourceGroup/$AksClusterName."
}

$storageAccountId = & az storage account show --name $StorageAccountName --resource-group $StorageResourceGroup --query id --output tsv 2>$null
$storageAccountId = ($storageAccountId | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($storageAccountId)) {
    Fail "Could not resolve storage account $StorageAccountName in $StorageResourceGroup."
}

Write-Host "    [6/7] Resolving AKS kubelet identity and validating RBAC..."

$aksCluster = Invoke-AzJson @("aks", "show", "--resource-group", $AksResourceGroup, "--name", $AksClusterName, "-o", "json")
if ($null -eq $aksCluster) {
    Fail "Could not query AKS cluster metadata for $AksResourceGroup/$AksClusterName."
}

$kubeletObjectId = $null
$kubeletIdentityResourceId = $null

if ($null -ne $aksCluster.identityProfile -and $null -ne $aksCluster.identityProfile.kubeletidentity) {
    $kubeletObjectId = ($aksCluster.identityProfile.kubeletidentity.objectId | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($kubeletObjectId)) {
        $kubeletObjectId = ($aksCluster.identityProfile.kubeletidentity.object_id | Out-String).Trim()
    }

    $kubeletIdentityResourceId = ($aksCluster.identityProfile.kubeletidentity.resourceId | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($kubeletIdentityResourceId)) {
        $kubeletIdentityResourceId = ($aksCluster.identityProfile.kubeletidentity.resource_id | Out-String).Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($kubeletObjectId) -and -not [string]::IsNullOrWhiteSpace($kubeletIdentityResourceId)) {
    $kubeletIdentity = Invoke-AzJson @("identity", "show", "--ids", $kubeletIdentityResourceId, "-o", "json")
    if ($null -ne $kubeletIdentity) {
        $kubeletObjectId = ($kubeletIdentity.principalId | Out-String).Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($kubeletObjectId)) {
    Fail "Could not resolve AKS kubelet identity object ID for $AksResourceGroup/$AksClusterName. Ensure the cluster has a kubelet identity and that your identity can read it."
}

# Validate all three required RBAC roles
$requiredRoles = @('Storage File Data SMB MI Admin', 'Storage Account Contributor', 'Storage File Data SMB Share Contributor')
$missingRoles = @()

foreach ($role in $requiredRoles) {
    $roleAssignmentCount = & az role assignment list --scope $storageAccountId --assignee-object-id $kubeletObjectId --role $role --query 'length(@)' --output tsv 2>$null
    $roleAssignmentCount = (($roleAssignmentCount | Out-String).Trim())
    if ([string]::IsNullOrWhiteSpace($roleAssignmentCount)) {
        $roleAssignmentCount = '0'
    }

    if ($roleAssignmentCount -eq '0') {
        $missingRoles += $role
    }
}

if ($missingRoles.Count -gt 0) {
    $missingRolesList = $missingRoles -join ', '
    Fail "AKS kubelet identity is missing required RBAC roles on $StorageAccountName : [$missingRolesList]. Assign these roles before provisioning."
}

Write-Host "    [7/7] Checking namespace availability..."
$existingNamespace = & kubectl get namespace $Namespace -o name 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    WARNING: Namespace '$Namespace' already exists. Proceeding with provisioning."
}

Write-Host 'Preflight validation complete.'
Write-Host ''

Write-Host "--> Creating namespace $Namespace..."
& kubectl create namespace $Namespace --dry-run=client -o yaml | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to create namespace.'
}

Write-Host "--> Enabling SMB OAuth on storage account '$StorageAccountName'..."
& az storage account update --name $StorageAccountName --resource-group $StorageResourceGroup --enable-smb-oauth true --min-tls-version TLS1_2 --output none
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to enable SMB OAuth on the storage account.'
}

$smbOAuthState = Invoke-AzJson @('storage', 'account', 'show', '--name', $StorageAccountName, '--resource-group', $StorageResourceGroup, '--query', '{legacy:enableSmbOauth,new:azureFilesIdentityBasedAuthentication.smbOAuthSettings.isSmbOAuthEnabled}', '-o', 'json')
$smbOAuthEnabled = "$(($smbOAuthState.legacy ?? $smbOAuthState.new) ?? '')".Trim().ToLowerInvariant()
if ($smbOAuthEnabled -ne 'true') {
    Fail 'Storage account SMB OAuth is not enabled after update call.'
}

if (-not $smbOAuthEnabled -and -not $smbOAuthStateKnown) {
    Write-Host "WARNING: Could not verify SMB OAuth state from Azure API response shape. Continuing with provisioning."
}

Write-Host "--> Creating StorageClass $StorageClassName..."
$storageClassContent = Get-Content (Join-Path $ManifestsDir 'storageclass-azurefile-mi.yaml') -Raw
$storageClassContent = $storageClassContent.Replace('name: devcontainer-azurefile-mi', "name: $StorageClassName")
$storageClassContent = $storageClassContent.Replace('REPLACE_STORAGE_RESOURCE_GROUP', $StorageResourceGroup)
$storageClassContent = $storageClassContent.Replace('REPLACE_STORAGE_ACCOUNT_NAME', $StorageAccountName)
$storageClassContent = $storageClassContent.Replace('REPLACE_SHARE_NAME', $ShareName)
Invoke-KubectlApplyText $storageClassContent

Write-Host '--> Applying LimitRange...'
$limitRangeContent = (Get-Content (Join-Path $ManifestsDir 'limit-range.yaml') -Raw).Replace('namespace: devcontainers', "namespace: $Namespace")
Invoke-KubectlApplyText $limitRangeContent

Write-Host '--> Applying ResourceQuota...'
$resourceQuotaContent = (Get-Content (Join-Path $ManifestsDir 'resource-quota.yaml') -Raw).Replace('namespace: devcontainers', "namespace: $Namespace")
Invoke-KubectlApplyText $resourceQuotaContent

Write-Host "--> Creating PersistentVolumeClaim in $Namespace..."
$pvcContent = Get-Content (Join-Path $ManifestsDir 'pvc.yaml') -Raw
$pvcContent = $pvcContent.Replace('namespace: devcontainers', "namespace: $Namespace")
$pvcContent = $pvcContent.Replace('storageClassName: azurefile-csi', "storageClassName: $StorageClassName")
Invoke-KubectlApplyText $pvcContent

Write-Host "--> Deploying dev-workspace in $Namespace..."
$deploymentContent = (Get-Content (Join-Path $ManifestsDir 'dev-workspace-deployment.yaml') -Raw).Replace('namespace: devcontainers', "namespace: $Namespace")
if (-not [string]::IsNullOrWhiteSpace($WorkspaceImage)) {
    $deploymentContent = $deploymentContent.Replace('image: myacr.azurecr.io/remote-devcontainer:latest', "image: $WorkspaceImage")
} elseif ($deploymentContent -match 'image:\s*myacr\.azurecr\.io/remote-devcontainer:latest') {
    Fail "Deployment manifest still references placeholder image 'myacr.azurecr.io/remote-devcontainer:latest'. Set DEV_WORKSPACE_IMAGE (for example: <acr-login-server>/remote-devcontainer:latest)."
}
Invoke-KubectlApplyText $deploymentContent

Write-Host "--> Waiting for deployment rollout in $Namespace..."
if (-not (Wait-DeploymentAvailable -Namespace $Namespace -DeploymentName 'dev-workspace' -TimeoutSeconds 240)) {
    Show-WorkspaceDiagnostics -Namespace $Namespace -StorageClassName $StorageClassName
    Fail 'dev-workspace deployment did not become ready within timeout. See diagnostics above.'
}

Write-Host ''
Write-Host '==> Done. To connect:'
Write-Host ''
Write-Host '    Option A - VS Code Kubernetes extension (recommended, no internet required from pod):'
Write-Host "      1. Open VS Code locally with the 'Dev Containers' + 'Kubernetes' extensions installed."
Write-Host "      2. Set the current kubectl namespace so the Dev Containers extension can see the pod:"
Write-Host "           kubectl config set-context --current --namespace=$Namespace"
Write-Host '      3. Open the Command Palette (F1) and run:'
Write-Host '           Dev Containers: Attach to Running Kubernetes Container...'
Write-Host '         OR: Kubernetes explorer -> expand cluster -> right-click the pod -> Attach Visual Studio Code'
Write-Host '      4. VS Code will not discover the pod unless kubectl is set to the correct namespace.'
Write-Host '      5. VS Code Server installs itself inside the pod automatically - no code-server credentials needed.'
Write-Host '      6. Reference attached-container-config.json in manifests/ for recommended extension/settings defaults.'
Write-Host ''
Write-Host '    Option B - VS Code Remote Tunnels (requires outbound internet from pod to Microsoft tunnel service):'
Write-Host "      kubectl exec -n $Namespace deploy/dev-workspace -- code tunnel --accept-server-license-terms"
Write-Host '      Then open the printed vscode.dev URL in VS Code or a browser.'
Write-Host ''
Write-Host '    To tail logs:'
Write-Host "      kubectl logs -n $Namespace deploy/dev-workspace -f"