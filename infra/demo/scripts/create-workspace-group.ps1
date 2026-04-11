#!/usr/bin/env pwsh

param(
    [Parameter(Position = 0)]
    [string]$GroupDisplayName = "shipyard-dev-workspace-creators",

    [Parameter(Position = 1)]
    [string]$MailNickname,

    [Parameter(Position = 2)]
    [ValidateSet('workspace-user', 'workspace-cluster-admin')]
    [string]$Purpose = 'workspace-user',

    [switch]$OutputJson
)

$ErrorActionPreference = 'Stop'

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

Require-Cmd az

$terraformVariableName = if ($Purpose -eq 'workspace-cluster-admin') {
    'workspace_cluster_admin_group_id'
}
else {
    'workspace_user_group_id'
}

$account = Invoke-AzJson @("account", "show", "-o", "json")
if ($null -eq $account) {
    Fail "Azure CLI is not logged in. Run 'az login' and retry."
}

if ([string]::IsNullOrWhiteSpace($MailNickname)) {
    $MailNickname = ($GroupDisplayName.ToLowerInvariant() -replace '[^a-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($MailNickname)) {
        $MailNickname = "shipyarddevworkspacecreators"
    }
}

$escapedName = $GroupDisplayName.Replace("'", "''")
$existing = Invoke-AzJson @("ad", "group", "list", "--filter", "displayName eq '$escapedName'", "--query", "[0].{id:id,displayName:displayName}", "-o", "json")

if ($null -eq $existing) {
    Write-Host "Creating Entra group '$GroupDisplayName'..."
    $created = Invoke-AzJson @("ad", "group", "create", "--display-name", $GroupDisplayName, "--mail-nickname", $MailNickname, "-o", "json")
    if ($null -eq $created -or [string]::IsNullOrWhiteSpace($created.id)) {
        Fail "Failed to create Entra group '$GroupDisplayName'."
    }
    $groupId = $created.id
}
else {
    Write-Host "Using existing Entra group '$($existing.displayName)'."
    $groupId = $existing.id
}

if ($OutputJson) {
    [PSCustomObject]@{
        groupDisplayName = $GroupDisplayName
        groupObjectId    = $groupId
        purpose          = $Purpose
        terraformVar     = $terraformVariableName
    } | ConvertTo-Json -Depth 3
    exit 0
}

Write-Host ""
Write-Host "Developer workspace group ready."
Write-Host "Group display name : $GroupDisplayName"
Write-Host "Group object ID    : $groupId"
Write-Host "Group purpose      : $Purpose"
Write-Host ""
Write-Host "Set this in infra/demo/terraform.tfvars:"
Write-Host "$terraformVariableName = \"$groupId\""

Write-Output $groupId
