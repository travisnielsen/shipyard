#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Username,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$StorageAccountName,

    [switch]$DeleteData
)

$ErrorActionPreference = 'Stop'

$Namespace = "devcontainer-$Username"
$StorageClassName = "devcontainer-azurefile-mi-$Username"
$ShareName = "devcontainer-$Username"

Write-Host "==> Deprovisioning workspace for '$Username'"
Write-Host "    Namespace    : $Namespace"
Write-Host "    StorageClass : $StorageClassName"
Write-Host "    File share   : $ShareName"
Write-Host ''

& kubectl get namespace $Namespace *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Namespace '$Namespace' not found - it may have already been deleted."
}
else {
    Write-Host "--> Deleting namespace '$Namespace' (cascades to all namespaced resources)..."
    & kubectl delete namespace $Namespace

    Write-Host '--> Waiting for namespace deletion to complete...'
    & kubectl wait --for=delete "namespace/$Namespace" --timeout=120s
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    Namespace deleted.'
    }
    else {
        Write-Host "    WARNING: namespace deletion timed out - check 'kubectl get namespace $Namespace'"
    }
}

& kubectl get storageclass $StorageClassName *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "INFO: StorageClass '$StorageClassName' not found - skipping."
}
else {
    Write-Host "--> Deleting StorageClass '$StorageClassName'..."
    & kubectl delete storageclass $StorageClassName
    Write-Host '    StorageClass deleted.'
}

if ($DeleteData) {
    Write-Host ''
    Write-Host 'WARNING: -DeleteData was specified.'
    Write-Host "  This will permanently delete Azure File Share '$ShareName'."
    Write-Host "  All workspace data for '$Username' will be lost."
    Write-Host ''
    $confirm = Read-Host "Type the username '$Username' to confirm permanent data deletion"
    if ($confirm -ne $Username) {
        Write-Host 'Confirmation did not match. Azure File Share retained.'
    }
    else {
        & az storage share-rm delete --storage-account $StorageAccountName --name $ShareName --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Azure File Share '$ShareName' deleted."
        }
        else {
            Write-Host '    WARNING: Share deletion failed or share not found - check manually.'
        }
    }
}
else {
    Write-Host "--> Retaining Azure File Share '$ShareName' (data preserved)."
    Write-Host '    To permanently delete the data, rerun with -DeleteData'
    Write-Host '    or delete the share manually in your storage account.'
}

Write-Host ''
Write-Host "==> Deprovision complete for '$Username'."