#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:AKS_CLUSTER_NAME) { throw 'AKS_CLUSTER_NAME is required.' }
if (-not $env:AKS_RESOURCE_GROUP) { throw 'AKS_RESOURCE_GROUP is required.' }
if (-not $env:AZURE_SUBSCRIPTION_ID) { throw 'AZURE_SUBSCRIPTION_ID is required.' }

$mode = if ($env:ARC_BOOTSTRAP_EXECUTION_MODE) { $env:ARC_BOOTSTRAP_EXECUTION_MODE } else { 'azure-control-plane' }
$scope = if ($env:ARC_RUNNER_SCOPE) { $env:ARC_RUNNER_SCOPE } else { 'repository' }
$configUrl = if ($env:ARC_RUNNER_CONFIG_URL) { $env:ARC_RUNNER_CONFIG_URL } else { '' }
$githubAppId = if ($env:ARC_GITHUB_APP_ID) { $env:ARC_GITHUB_APP_ID } else { '' }
$githubAppInstallationId = if ($env:ARC_GITHUB_APP_INSTALLATION_ID) { $env:ARC_GITHUB_APP_INSTALLATION_ID } else { '' }
$githubAppPrivateKey = if ($env:ARC_GITHUB_APP_PRIVATE_KEY) { $env:ARC_GITHUB_APP_PRIVATE_KEY } else { '' }
$labels = if ($env:ARC_RUNNER_LABELS) { $env:ARC_RUNNER_LABELS } else { 'shipyard-private,linux,aks' }
$minReplicas = if ($env:ARC_RUNNER_MIN_REPLICAS) { $env:ARC_RUNNER_MIN_REPLICAS } else { '0' }
$maxReplicas = if ($env:ARC_RUNNER_MAX_REPLICAS) { $env:ARC_RUNNER_MAX_REPLICAS } else { '5' }
$runnerNodePool = if ($env:ARC_RUNNER_NODEPOOL_NAME) { $env:ARC_RUNNER_NODEPOOL_NAME } else { 'arc' }
$runnerImage = if ($env:ARC_RUNNER_IMAGE) { $env:ARC_RUNNER_IMAGE } else { 'ghcr.io/actions/actions-runner:latest' }
$controllerReleaseName = if ($env:ARC_CONTROLLER_RELEASE_NAME) { $env:ARC_CONTROLLER_RELEASE_NAME } else { 'arc-controller' }
$controllerChartVersion = if ($env:ARC_CONTROLLER_CHART_VERSION) { $env:ARC_CONTROLLER_CHART_VERSION } else { '0.12.1' }
$controllerChartRef = if ($env:ARC_CONTROLLER_CHART_REF) { $env:ARC_CONTROLLER_CHART_REF } else { 'oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller' }
$runnerReleaseName = if ($env:ARC_RUNNER_RELEASE_NAME) { $env:ARC_RUNNER_RELEASE_NAME } else { 'shipyard-runner-set' }
$runnerChartVersion = if ($env:ARC_RUNNER_CHART_VERSION) { $env:ARC_RUNNER_CHART_VERSION } else { '0.12.1' }
$runnerChartRef = if ($env:ARC_RUNNER_CHART_REF) { $env:ARC_RUNNER_CHART_REF } else { 'oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set' }
$runnerSecretName = if ($env:ARC_RUNNER_SECRET_NAME) { $env:ARC_RUNNER_SECRET_NAME } else { 'arc-runner-set-secret' }

Write-Host "[bootstrap-arc] mode=$mode cluster=$($env:AKS_CLUSTER_NAME) rg=$($env:AKS_RESOURCE_GROUP)"
Write-Host "[bootstrap-arc] scope=$scope config_url=$configUrl labels=$labels"
Write-Host "[bootstrap-arc] replicas=$minReplicas-$maxReplicas nodepool=$runnerNodePool"

if ($mode -eq 'gitops') {
  Write-Host '[bootstrap-arc] gitops mode selected; no imperative install performed in scaffold.'
  exit 0
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw '[bootstrap-arc] az CLI is required for azure-control-plane mode.'
}

if ([string]::IsNullOrWhiteSpace($configUrl)) {
  throw '[bootstrap-arc] ARC_RUNNER_CONFIG_URL is required in azure-control-plane mode.'
}

if ([string]::IsNullOrWhiteSpace($githubAppId) -or [string]::IsNullOrWhiteSpace($githubAppInstallationId) -or [string]::IsNullOrWhiteSpace($githubAppPrivateKey)) {
  throw '[bootstrap-arc] ARC_GITHUB_APP_ID, ARC_GITHUB_APP_INSTALLATION_ID, and ARC_GITHUB_APP_PRIVATE_KEY are required.'
}

az account set --subscription $env:AZURE_SUBSCRIPTION_ID | Out-Null

function Invoke-AksCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  $resultJson = az aks command invoke `
    --resource-group $env:AKS_RESOURCE_GROUP `
    --name $env:AKS_CLUSTER_NAME `
    --command $Command `
    --output json

  $result = $resultJson | ConvertFrom-Json
  if ($null -eq $result.exitCode -or [int]$result.exitCode -ne 0) {
    throw "[bootstrap-arc] remote command failed (exitCode=$($result.exitCode)): $Command`n$resultJson"
  }
}

# Namespace + controller install is idempotent through kubectl apply and helm upgrade --install.
Invoke-AksCommand -Command 'kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -'
Invoke-AksCommand -Command 'kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -'

$privateKeyIndented = (($githubAppPrivateKey -replace "`r`n", "`n") -split "`n" | ForEach-Object { "    $_" }) -join "`n"

Invoke-AksCommand -Command @"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $runnerSecretName
  namespace: arc-runners
type: Opaque
stringData:
  github_app_id: "$githubAppId"
  github_app_installation_id: "$githubAppInstallationId"
  github_app_private_key: |
$privateKeyIndented
EOF
"@

Invoke-AksCommand -Command "helm upgrade --install $controllerReleaseName $controllerChartRef --namespace arc-systems --version $controllerChartVersion"
Invoke-AksCommand -Command @"
helm upgrade --install $runnerReleaseName $runnerChartRef --namespace arc-runners --version $runnerChartVersion -f - <<'EOF'
githubConfigUrl: $configUrl
githubConfigSecret: $runnerSecretName
minRunners: $minReplicas
maxRunners: $maxReplicas
template:
  spec:
    containers:
      - name: runner
        image: $runnerImage
    nodeSelector:
      kubernetes.azure.com/agentpool: $runnerNodePool
    tolerations:
      - key: workload
        operator: Equal
        value: github-runner
        effect: NoSchedule
EOF
"@

Write-Host '[bootstrap-arc] ARC controller and runner set helm install commands completed.'
