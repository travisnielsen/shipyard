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
$ManifestsDir = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'manifests'
$ManifestsDir = [System.IO.Path]::GetFullPath($ManifestsDir)

function Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message"
    exit 1
}

function Require-Cmd {
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

Write-Host "==> Provisioning workspace for '$Username' in namespace '$Namespace'"
Write-Host "    Storage RG      : $StorageResourceGroup"
Write-Host "    Storage account : $StorageAccountName"
Write-Host "    File share      : $ShareName"
Write-Host "    StorageClass    : $StorageClassName"
Write-Host ''

Require-Cmd kubectl
Require-Cmd az

Write-Host '--> Validating AKS managed-identity storage prerequisites...'

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

if (([int]$serverMajor -lt 1) -or (([int]$serverMajor -eq 1) -and ([int]$serverMinor -lt 34))) {
    Fail "AKS Kubernetes version $serverMajor.$serverMinorRaw does not meet minimum 1.34 for Azure Files managed identity mount mode."
}

& kubectl get csidriver file.csi.azure.com -o name *> $null
if ($LASTEXITCODE -ne 0) {
    Fail 'Azure Files CSI driver (file.csi.azure.com) is not available in the current cluster.'
}

$AksResourceGroup = $env:AKS_RESOURCE_GROUP
$AksClusterName = $env:AKS_CLUSTER_NAME

if ([string]::IsNullOrWhiteSpace($AksResourceGroup) -or [string]::IsNullOrWhiteSpace($AksClusterName)) {
    $discovered = Invoke-AzJson aks list -o json
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

$kubeletObjectId = & az aks show --resource-group $AksResourceGroup --name $AksClusterName --query "coalesce(identityProfile.kubeletidentity.objectId, identityProfile.kubeletidentity.object_id)" --output tsv 2>$null
$kubeletObjectId = ($kubeletObjectId | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($kubeletObjectId)) {
    Fail "Could not resolve AKS kubelet identity object ID for $AksResourceGroup/$AksClusterName."
}

$storageAccountId = & az storage account show --name $StorageAccountName --resource-group $StorageResourceGroup --query id --output tsv 2>$null
$storageAccountId = ($storageAccountId | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($storageAccountId)) {
    Fail "Could not resolve storage account $StorageAccountName in $StorageResourceGroup."
}

$roleAssignmentCount = & az role assignment list --scope $storageAccountId --assignee-object-id $kubeletObjectId --role 'Storage File Data SMB MI Admin' --query 'length(@)' --output tsv 2>$null
$roleAssignmentCount = (($roleAssignmentCount | Out-String).Trim())
if ([string]::IsNullOrWhiteSpace($roleAssignmentCount)) {
    $roleAssignmentCount = '0'
}

if ($roleAssignmentCount -eq '0') {
    Fail "AKS kubelet identity does not have 'Storage File Data SMB MI Admin' on $StorageAccountName. Assign it before provisioning."
}

Write-Host "--> Creating namespace $Namespace..."
& kubectl create namespace $Namespace --dry-run=client -o yaml | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to create namespace.'
}

Write-Host "--> Enabling SMB OAuth on storage account '$StorageAccountName'..."
& az storage account update --name $StorageAccountName --resource-group $StorageResourceGroup --enable-smb-oauth true --output none
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to enable SMB OAuth on the storage account.'
}

$smbOAuthEnabled = & az storage account show --name $StorageAccountName --resource-group $StorageResourceGroup --query enableSmbOauth --output tsv 2>$null
$smbOAuthEnabled = (($smbOAuthEnabled | Out-String).Trim())
if ($smbOAuthEnabled -ne 'true') {
    Fail 'Storage account SMB OAuth is not enabled after update call.'
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
Invoke-KubectlApplyText $deploymentContent

Write-Host ''
Write-Host '==> Done. To connect:'
Write-Host ''
Write-Host '    Option A - VS Code Kubernetes extension (recommended, no internet required from pod):'
Write-Host "      1. Open VS Code locally with the 'Dev Containers' + 'Kubernetes' extensions installed."
Write-Host '      2. Open the Command Palette (F1) and run:'
Write-Host '           Dev Containers: Attach to Running Kubernetes Container...'
Write-Host '         OR: Kubernetes explorer -> expand cluster -> right-click the pod -> Attach Visual Studio Code'
Write-Host '      3. VS Code Server installs itself inside the pod automatically - no code-server credentials needed.'
Write-Host '      4. Reference attached-container-config.json in manifests/ for recommended extension/settings defaults.'
Write-Host ''
Write-Host '    Option B - VS Code Remote Tunnels (requires outbound internet from pod to Microsoft tunnel service):'
Write-Host "      kubectl exec -n $Namespace deploy/dev-workspace -- code tunnel --accept-server-license-terms"
Write-Host '      Then open the printed vscode.dev URL in VS Code or a browser.'
Write-Host ''
Write-Host '    To tail logs:'
Write-Host "      kubectl logs -n $Namespace deploy/dev-workspace -f"