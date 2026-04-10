#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Username,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$StorageResourceGroup,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$StorageAccountName,

    [Parameter(Position = 3)]
    [string]$ShareName,

    [Parameter(Position = 4)]
    [string]$WorkspaceImage
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ShareName)) {
    $ShareName = "devcontainer-$Username"
}

$Namespace = "devcontainer-$Username"
$StorageClassName = "devcontainer-azurefile-mi-$Username"
$PvName = "$($Namespace)-pv"
$PvcName = 'dev-workspace-pvc'
$DeploymentName = 'dev-workspace'
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

function Invoke-KubectlJson {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = & kubectl @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String))) {
        return $null
    }

    return ($output | Out-String | ConvertFrom-Json)
}

function Write-TempYaml {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Wait-PvcBound {
    param(
        [string]$Namespace,
        [string]$PvcName,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $pvc = Invoke-KubectlJson @('get', 'pvc', $PvcName, '-n', $Namespace, '-o', 'json')
        if ($null -eq $pvc) {
            Write-Host "    Waiting for PVC '$PvcName' to appear..."
            Start-Sleep -Seconds 5
            continue
        }

        $phase = ''
        if ($null -ne $pvc.status -and $null -ne $pvc.status.phase) {
            $phase = ($pvc.status.phase | Out-String).Trim()
        }

        Write-Host "    PVC status: $phase"
        if ($phase -eq 'Bound') {
            return $true
        }

        Start-Sleep -Seconds 5
    }

    return $false
}

function Wait-DeploymentAvailable {
    param(
        [string]$Namespace,
        [string]$DeploymentName,
        [int]$TimeoutSeconds = 240
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $deployment = Invoke-KubectlJson @('get', 'deployment', $DeploymentName, '-n', $Namespace, '-o', 'json')
        if ($null -eq $deployment) {
            Write-Host "    Waiting for deployment '$DeploymentName' to become readable..."
            Start-Sleep -Seconds 5
            continue
        }

        $desired = 1
        if ($null -ne $deployment.spec -and $null -ne $deployment.spec.replicas) {
            $desired = [int]$deployment.spec.replicas
        }

        $updated = 0
        if ($null -ne $deployment.status -and $null -ne $deployment.status.updatedReplicas) {
            $updated = [int]$deployment.status.updatedReplicas
        }

        $available = 0
        if ($null -ne $deployment.status -and $null -ne $deployment.status.availableReplicas) {
            $available = [int]$deployment.status.availableReplicas
        }

        $ready = 0
        if ($null -ne $deployment.status -and $null -ne $deployment.status.readyReplicas) {
            $ready = [int]$deployment.status.readyReplicas
        }

        Write-Host "    Rollout progress: updated=$updated/$desired ready=$ready/$desired available=$available/$desired"

        if ($updated -ge $desired -and $available -ge $desired -and $ready -ge $desired) {
            return $true
        }

        Start-Sleep -Seconds 10
    }

    return $false
}

function Show-Diagnostics {
    param(
        [string]$Namespace,
        [string]$StorageClassName,
        [string]$PvName,
        [string]$PvcName
    )

    Write-Host "--> Diagnostics for namespace '$Namespace'"
    & kubectl get pods -n $Namespace -o wide
    & kubectl get pvc -n $Namespace
    & kubectl describe pvc $PvcName -n $Namespace
    & kubectl get pv $PvName -o yaml
    & kubectl get events -n $Namespace --sort-by=.lastTimestamp
    Write-Host '--> kube-system CSI resources:'
    & kubectl get deployment,daemonset,statefulset -n kube-system | Select-String 'azurefile|csi|file'
}

Write-Host "==> Provisioning workspace (v2 static storage) for '$Username' in namespace '$Namespace'"
Write-Host "    Storage RG      : $StorageResourceGroup"
Write-Host "    Storage account : $StorageAccountName"
Write-Host "    File share      : $ShareName"
Write-Host "    StorageClass    : $StorageClassName"
Write-Host "    PV              : $PvName"
Write-Host ''

Require-Cmd kubectl
Require-Cmd az

$csiDriverOutput = & kubectl get csidriver file.csi.azure.com -o name 2>&1
if ($LASTEXITCODE -ne 0) {
    Fail 'Azure Files CSI driver (file.csi.azure.com) is not available in the current cluster.'
}

$azureFileController = & kubectl get deployment csi-azurefile-controller -n kube-system -o name 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'WARNING: csi-azurefile-controller is not present. Dynamic provisioning is broken, continuing with static PV/PVC workaround.'
}

if ([string]::IsNullOrWhiteSpace($WorkspaceImage)) {
    $WorkspaceImage = $env:DEV_WORKSPACE_IMAGE
}

if ([string]::IsNullOrWhiteSpace($WorkspaceImage)) {
    $acrList = Invoke-AzJson @('acr', 'list', '--resource-group', $StorageResourceGroup, '-o', 'json')
    if ($null -ne $acrList -and $acrList.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace(($acrList[0].loginServer | Out-String).Trim())) {
        $WorkspaceImage = "$(($acrList[0].loginServer | Out-String).Trim())/remote-devcontainer:latest"
    }
    elseif ($null -ne $acrList -and $acrList.Count -gt 1) {
        Fail "Multiple ACR registries found in resource group '$StorageResourceGroup'. Set DEV_WORKSPACE_IMAGE or pass -WorkspaceImage."
    }
    else {
        Fail "Could not resolve workspace image automatically. Set DEV_WORKSPACE_IMAGE or pass -WorkspaceImage."
    }
}

Write-Host "    Workspace image : $WorkspaceImage"
Write-Host ''

Write-Host "--> Creating namespace '$Namespace'..."
& kubectl create namespace $Namespace --dry-run=client -o yaml | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to create namespace.'
}

Write-Host "--> Cleaning previous workspace resources..."
& kubectl delete deployment $DeploymentName -n $Namespace --ignore-not-found
& kubectl delete pvc $PvcName -n $Namespace --ignore-not-found
& kubectl delete pv $PvName --ignore-not-found
& kubectl delete storageclass $StorageClassName --ignore-not-found

Write-Host "--> Ensuring Azure File share '$ShareName' exists..."
& az storage share-rm create --resource-group $StorageResourceGroup --storage-account $StorageAccountName --name $ShareName --quota 100 --output none
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to create or validate Azure File share.'
}

$tempRoot = [System.IO.Path]::GetTempPath()
$pvPath = Join-Path $tempRoot "$($PvName).yaml"
$pvcPath = Join-Path $tempRoot "$($Namespace)-$($PvcName).yaml"

$pvYaml = @"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PvName
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $StorageClassName
  claimRef:
    namespace: $Namespace
    name: $PvcName
  csi:
    driver: file.csi.azure.com
    readOnly: false
    volumeHandle: $PvName
    volumeAttributes:
      resourceGroup: $StorageResourceGroup
      storageAccount: $StorageAccountName
      shareName: $ShareName
      mountWithManagedIdentity: \"true\"
      storeAccountKey: \"false\"
  mountOptions:
    - dir_mode=0755
    - file_mode=0755
    - uid=1000
    - gid=1000
    - mfsymlinks
    - cache=strict
    - nosharesock
    - actimeo=30
    - nobrl
"@

$pvcYaml = @"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PvcName
  namespace: $Namespace
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: $StorageClassName
  volumeName: $PvName
  resources:
    requests:
      storage: 10Gi
"@

Write-Host '--> Writing temporary PV/PVC manifests...'
Write-TempYaml -Path $pvPath -Content $pvYaml
Write-TempYaml -Path $pvcPath -Content $pvcYaml

$pvNameCheck = & kubectl create --dry-run=client -f $pvPath -o jsonpath='{.metadata.name}'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($pvNameCheck | Out-String).Trim())) {
    Fail "Generated PV manifest is invalid: $pvPath"
}

$pvcNameCheck = & kubectl create --dry-run=client -f $pvcPath -o jsonpath='{.metadata.name}'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($pvcNameCheck | Out-String).Trim())) {
    Fail "Generated PVC manifest is invalid: $pvcPath"
}

Write-Host '--> Applying static PV/PVC...'
& kubectl apply -f $pvPath
if ($LASTEXITCODE -ne 0) {
    Fail "Failed to apply PV manifest: $pvPath"
}

& kubectl apply -f $pvcPath
if ($LASTEXITCODE -ne 0) {
    Fail "Failed to apply PVC manifest: $pvcPath"
}

Write-Host '--> Waiting for PVC to bind...'
if (-not (Wait-PvcBound -Namespace $Namespace -PvcName $PvcName -TimeoutSeconds 120)) {
    Show-Diagnostics -Namespace $Namespace -StorageClassName $StorageClassName -PvName $PvName -PvcName $PvcName
    Fail 'PVC did not reach Bound state.'
}

Write-Host "--> Deploying '$DeploymentName' in namespace '$Namespace'..."
$deploymentPath = Join-Path $ManifestsDir 'dev-workspace-deployment.yaml'
$deploymentContent = Get-Content $deploymentPath -Raw
$deploymentContent = $deploymentContent.Replace('namespace: devcontainers', "namespace: $Namespace")
$deploymentContent = $deploymentContent.Replace('image: myacr.azurecr.io/remote-devcontainer:latest', "image: $WorkspaceImage")
$deploymentContent | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to apply deployment manifest.'
}

Write-Host "--> Waiting for deployment rollout in $Namespace..."
if (-not (Wait-DeploymentAvailable -Namespace $Namespace -DeploymentName $DeploymentName -TimeoutSeconds 240)) {
    Show-Diagnostics -Namespace $Namespace -StorageClassName $StorageClassName -PvName $PvName -PvcName $PvcName
    Fail 'Deployment did not become ready within timeout.'
}

Write-Host ''
Write-Host '==> Done. Workspace is ready.'
Write-Host "    Namespace: $Namespace"
Write-Host "    Pod check: kubectl get pods -n $Namespace -o wide"
Write-Host "    Logs     : kubectl logs -n $Namespace deploy/$DeploymentName -f"
