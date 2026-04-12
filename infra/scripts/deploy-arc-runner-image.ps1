[CmdletBinding()]
param(
  [string]$VarFile = "terraform.tfvars",
  [string]$RunnerImageRepo = "actions-runner",
  [string]$RunnerImageTag = "",
  [switch]$SkipBaseApply
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tfDir = Resolve-Path (Join-Path $scriptDir "..")
$repoRoot = Resolve-Path (Join-Path $tfDir "..")

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
  throw 'terraform is required.'
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw 'Azure CLI (az) is required.'
}

$resolvedVarFile = if ([System.IO.Path]::IsPathRooted($VarFile)) { $VarFile } else { Join-Path $tfDir $VarFile }
if (-not (Test-Path $resolvedVarFile)) {
  throw "Terraform var-file not found: $resolvedVarFile"
}

if ([string]::IsNullOrWhiteSpace($RunnerImageTag)) {
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd) {
    try {
      $RunnerImageTag = (git -C $repoRoot rev-parse --short HEAD).Trim()
    } catch {
      $RunnerImageTag = (Get-Date -Format 'yyyyMMddHHmmss')
    }
  } else {
    $RunnerImageTag = (Get-Date -Format 'yyyyMMddHHmmss')
  }
}

Push-Location $tfDir
try {
  Write-Host '[deploy-arc-runner-image] terraform init'
  terraform init

  Write-Host '[deploy-arc-runner-image] terraform validate'
  terraform validate

  if (-not $SkipBaseApply) {
    Write-Host '[deploy-arc-runner-image] terraform apply (base infrastructure)'
    terraform apply -auto-approve -var-file="$resolvedVarFile"
  }

  Write-Host '[deploy-arc-runner-image] reading Terraform outputs'
  $acrLoginServer = (terraform output -raw acr_login_server).Trim()
  $acrTaskAgentPoolName = (terraform output -raw acr_task_agentpool_name).Trim()

  if ([string]::IsNullOrWhiteSpace($acrTaskAgentPoolName)) {
    throw 'acr_task_agentpool_name output is empty. Ensure enable_private_acr_tasks=true and apply has completed.'
  }

  $acrName = $acrLoginServer.Split('.')[0]
  $targetImage = "$acrLoginServer/$RunnerImageRepo`:$RunnerImageTag"

  Write-Host "[deploy-arc-runner-image] building $targetImage using private ACR Task pool $acrTaskAgentPoolName"
  az acr build `
    --registry "$acrName" `
    --agent-pool "$acrTaskAgentPoolName" `
    --file "$repoRoot/infra/github-runner/Dockerfile.runner" `
    --image "$RunnerImageRepo`:$RunnerImageTag" `
    --image "$RunnerImageRepo`:latest" `
    "$repoRoot"

  $arcBootstrapEnabled = (terraform output -raw arc_bootstrap_enabled).Trim()

  Write-Host "[deploy-arc-runner-image] terraform apply (set arc_runner_image=$targetImage)"
  if ($arcBootstrapEnabled -eq 'true') {
    terraform apply -auto-approve -var-file="$resolvedVarFile" -var "arc_runner_image=$targetImage" -replace=terraform_data.arc_bootstrap[0]
  } else {
    terraform apply -auto-approve -var-file="$resolvedVarFile" -var "arc_runner_image=$targetImage"
  }

  Write-Host '[deploy-arc-runner-image] complete'
  Write-Host "Published image: $targetImage"
}
finally {
  Pop-Location
}
