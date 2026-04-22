#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Username,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$StorageAccountName,

    [Parameter(Position = 2)]
    [string]$DeveloperIdentity,

    [switch]$DeleteData
)

$ErrorActionPreference = 'Stop'

$Namespace = "devcontainer-$Username"
$StorageClassName = "devcontainer-azurefile-mi-$Username"
$ShareName = "devcontainer-$Username"
$WorkspaceAksNamespaceRole = if ([string]::IsNullOrWhiteSpace($env:WORKSPACE_AKS_NAMESPACE_ROLE)) { 'Azure Kubernetes Service RBAC Writer' } else { $env:WORKSPACE_AKS_NAMESPACE_ROLE }
$WorkspaceStorageRole = if ([string]::IsNullOrWhiteSpace($env:WORKSPACE_STORAGE_ROLE)) { 'Storage File Data SMB Share Contributor' } else { $env:WORKSPACE_STORAGE_ROLE }

if ([string]::IsNullOrWhiteSpace($DeveloperIdentity)) {
    $DeveloperIdentity = $env:DEV_WORKSPACE_DEVELOPER_IDENTITY
}
if ([string]::IsNullOrWhiteSpace($DeveloperIdentity) -and $Username.Contains('@')) {
    $DeveloperIdentity = $Username
}

function Invoke-AzJson {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String))) {
        return $null
    }

    return ($output | Out-String | ConvertFrom-Json)
}

function Resolve-DeveloperObjectId {
    param([string]$Identity)

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return $null
    }

    if ($Identity -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return $Identity
    }

    $user = Invoke-AzJson @('ad', 'user', 'show', '--id', $Identity, '-o', 'json')
    if ($null -eq $user) {
        return $null
    }

    return ($user.id | Out-String).Trim()
}

function Remove-RoleAssignments {
    param(
        [string]$Scope,
        [string]$Role,
        [string]$PrincipalId
    )

    $assignmentIdsRaw = & az role assignment list --scope $Scope --assignee-object-id $PrincipalId --role $Role --query '[].id' --output tsv 2>$null
    if ($LASTEXITCODE -ne 0) {
        return
    }

    $assignmentIds = @($assignmentIdsRaw | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })
    foreach ($assignmentId in $assignmentIds) {
        & az role assignment delete --ids $assignmentId --output none 2>$null | Out-Null
    }
}

Write-Host "==> Deprovisioning workspace for '$Username'"
Write-Host "    Namespace    : $Namespace"
Write-Host "    StorageClass : $StorageClassName"
Write-Host "    File share   : $ShareName"
Write-Host ''

$developerObjectId = Resolve-DeveloperObjectId -Identity $DeveloperIdentity

$aksResourceGroup = $env:AKS_RESOURCE_GROUP
$aksClusterName = $env:AKS_CLUSTER_NAME
if ([string]::IsNullOrWhiteSpace($aksResourceGroup) -or [string]::IsNullOrWhiteSpace($aksClusterName)) {
    $clusters = Invoke-AzJson @('aks', 'list', '-o', 'json')
    if ($null -ne $clusters -and $clusters.Count -eq 1) {
        $aksResourceGroup = $clusters[0].resourceGroup
        $aksClusterName = $clusters[0].name
    }
}

$aksResourceId = $null
if (-not [string]::IsNullOrWhiteSpace($aksResourceGroup) -and -not [string]::IsNullOrWhiteSpace($aksClusterName)) {
    $aks = Invoke-AzJson @('aks', 'show', '--resource-group', $aksResourceGroup, '--name', $aksClusterName, '--query', '{id:id}', '-o', 'json')
    if ($null -ne $aks) {
        $aksResourceId = ($aks.id | Out-String).Trim()
    }
}

$storageAccountId = (& az storage account show --name $StorageAccountName --query id --output tsv 2>$null | Out-String).Trim()

if (-not [string]::IsNullOrWhiteSpace($developerObjectId) -and -not [string]::IsNullOrWhiteSpace($aksResourceId)) {
    $namespaceScope = "$aksResourceId/namespaces/$Namespace"
    Write-Host '--> Removing namespace-scoped AKS RBAC assignment(s) for developer...'
    Remove-RoleAssignments -Scope $namespaceScope -Role $WorkspaceAksNamespaceRole -PrincipalId $developerObjectId
}
else {
    Write-Host 'INFO: Skipping AKS RBAC cleanup (set AKS_RESOURCE_GROUP/AKS_CLUSTER_NAME and developer identity for full cleanup).'
}

if (-not [string]::IsNullOrWhiteSpace($developerObjectId) -and -not [string]::IsNullOrWhiteSpace($storageAccountId)) {
    $shareScope = "$storageAccountId/fileServices/default/fileshares/$ShareName"
    Write-Host '--> Removing share-scoped storage RBAC assignment(s) for developer...'
    Remove-RoleAssignments -Scope $shareScope -Role $WorkspaceStorageRole -PrincipalId $developerObjectId
}
else {
    Write-Host 'INFO: Skipping storage RBAC cleanup (could not resolve storage account ID and/or developer identity).'
}

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