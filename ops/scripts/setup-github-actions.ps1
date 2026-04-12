#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$GitHubOwner,
    [Parameter(Mandatory = $true, Position = 2)]
    [string]$GitHubRepo,
    [Parameter(Position = 3)]
    [string]$SubjectPattern,
    [Parameter(Position = 4)]
    [string]$AppName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SubjectPattern)) {
    $SubjectPattern = "repo:$GitHubOwner/$GitHubRepo`:ref:refs/heads/main"
}
if ([string]::IsNullOrWhiteSpace($AppName)) {
    $AppName = "shipyard-$GitHubOwner-$GitHubRepo-gha"
}
$federatedName = "github-$GitHubOwner-$GitHubRepo-oidc"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'az CLI is required.'
}

az account set --subscription $SubscriptionId | Out-Null
$tenantId = (az account show --query tenantId -o tsv)

$appId = (az ad app list --display-name $AppName --query "[0].appId" -o tsv)
if ([string]::IsNullOrWhiteSpace($appId)) {
    $appId = (az ad app create --display-name $AppName --query appId -o tsv)
}

$appObjectId = (az ad app show --id $appId --query id -o tsv)
$spObjectId = (az ad sp show --id $appId --query id -o tsv 2>$null)
if ([string]::IsNullOrWhiteSpace($spObjectId)) {
    $spObjectId = (az ad sp create --id $appId --query id -o tsv)
}

$existingFcCount = (az ad app federated-credential list --id $appObjectId --query "[?name=='$federatedName'] | length(@)" -o tsv)
if ($existingFcCount -eq '0') {
    $jsonPath = Join-Path ([System.IO.Path]::GetTempPath()) ("$federatedName.json")
    @{
        name = $federatedName
        issuer = 'https://token.actions.githubusercontent.com'
        subject = $SubjectPattern
        description = 'Shipyard GitHub OIDC federation'
        audiences = @('api://AzureADTokenExchange')
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding utf8

    az ad app federated-credential create --id $appObjectId --parameters $jsonPath | Out-Null
    Remove-Item -Path $jsonPath -Force
}

Write-Host "AZURE_CLIENT_ID=$appId"
Write-Host "AZURE_TENANT_ID=$tenantId"
Write-Host "AZURE_SUBSCRIPTION_ID=$SubscriptionId"
Write-Host "GITHUB_SUBJECT_PATTERN=$SubjectPattern"
Write-Host "ARC_RUNTIME_PRINCIPAL_ID=$spObjectId"
Write-Host "FEDERATED_APP_OBJECT_ID=$appObjectId"
Write-Host "NOTE=RBAC role assignments are managed by Terraform, not this setup script."
