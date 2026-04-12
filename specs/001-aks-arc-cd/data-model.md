# Data Model: AKS ARC GitHub Build Agents

## Entity: RunnerSetConfig

- Description: Configuration contract for ARC autoscaling runner set behavior.
- Fields:
  - `name` (string, required): Logical runner set name.
  - `namespace` (string, required): Kubernetes namespace for runner pods.
  - `githubScope` (enum: `repository|organization`, required): Target GitHub scope.
  - `githubConfigUrl` (string, required): Repo/org URL used by ARC.
  - `labels` (string[], required): Runner labels exposed to workflows.
  - `minRunners` (integer >= 0, required): Floor capacity.
  - `maxRunners` (integer >= minRunners, required): Ceiling capacity.
  - `runnerImage` (string, optional): Runner container image override.
  - `nodeSelector` (map<string,string>, optional): Scheduling constraints.
  - `tolerations` (array, optional): Tolerations matching runner pool taints.
- Validation rules:
  - `maxRunners >= minRunners`.
  - `labels` must include at least one stable label used in workflows.
  - `githubConfigUrl` must match declared `githubScope`.

## Entity: RunnerNodePoolConfig

- Description: AKS node pool configuration dedicated to ARC runner workloads.
- Fields:
  - `name` (string, required): Runner pool name.
  - `vmSize` (string, required): VM SKU for runners.
  - `enableAutoScaling` (boolean, required): Autoscaling toggle.
  - `minCount` (integer >= 0, required): Minimum node count (prefer `0` where supported).
  - `maxCount` (integer >= minCount, required): Maximum node count.
  - `labels` (map<string,string>, required): Includes runner workload marker.
  - `taints` (string[], required): Isolates runner nodes from non-runner workloads.
- Validation rules:
  - `minCount` must be set to `0` when platform supports scale-to-zero for chosen pool mode.
  - ARC runner pod scheduling policy must match labels/taints defined here.
  - Runner pool taints must prevent accidental workspace/system workload scheduling.

## Entity: FederationConfig

- Description: Entra federation trust and permissions used by GitHub workflows.
- Fields:
  - `appRegistrationName` (string, required): Entra app display name.
  - `clientId` (string, generated): App/client identifier.
  - `tenantId` (string, required): Entra tenant ID.
  - `subscriptionId` (string, required): Azure subscription ID.
  - `repository` (string, required): `owner/repo` identifier.
  - `subject` (string, required): Federated credential subject claim.
  - `audiences` (string[], required): Token audience list (`api://AzureADTokenExchange`).
  - `roleAssignments` (array, required): Least-privilege role bindings.
- Validation rules:
  - `subject` must map to intended branch/environment pattern.
  - Role assignments must be scoped to RG or resource level, not subscription-owner broad roles.

## Entity: DevcontainerImageBuildConfig

- Description: CI/CD workflow configuration for devcontainer image publishing.
- Fields:
  - `triggerPaths` (string[], required): Must include `devcontainer/**`.
  - `workflowName` (string, required): Human-readable workflow name.
  - `imageRepository` (string, required): Target ACR repository path.
  - `imageTagStrategy` (enum: `sha|semver|branch-sha`, required): Tagging policy.
  - `acrLoginServer` (string, required): ACR endpoint from infra outputs.
  - `pushEnabled` (boolean, required): Publish toggle for default branch.
- Validation rules:
  - Trigger paths must exclude unrelated repo paths.
  - Push step requires successful Azure OIDC login and ACR push rights.

## Entity: ScriptInventory

- Description: Mapping of workspace scripts to runtime domain.
- Fields:
  - `path` (string, required): Script file path.
  - `domain` (enum: `control-plane|in-container`, required): Execution domain.
  - `shell` (enum: `bash|powershell`, required): Runtime shell.
  - `purpose` (string, required): Operational function.
- Validation rules:
  - `control-plane` scripts must be under `ops/scripts`.
  - `in-container` scripts must be under `devcontainer/scripts`.

## Entity: ArcBootstrapExecutionConfig

- Description: Selected operational mode for ARC bootstrap without jump-host dependency.
- Fields:
  - `mode` (enum: `azure-control-plane|gitops`, required): Bootstrap execution mode.
  - `requiresPrivateReachabilityFromExecutionHost` (boolean, required): Must be `false` for selected default mode.
  - `idempotent` (boolean, required): Re-runs produce converged state.
  - `fallbackMode` (enum: `gitops`, optional): Secondary mode.
- Validation rules:
  - `requiresPrivateReachabilityFromExecutionHost` must remain `false` for default pipeline path.
  - Bootstrap mode must preserve private API posture and avoid dedicated jump hosts.

## Relationships

- `FederationConfig` secures `DevcontainerImageBuildConfig` workflow authentication.
- `RunnerSetConfig` is consumed by GitHub workflows that target private runner labels.
- `RunnerNodePoolConfig` constrains `RunnerSetConfig` scheduling placement.
- `ScriptInventory` constrains docs/workflows referencing operational scripts.

## State Transitions

### RunnerSet lifecycle

1. `defined` -> 2. `deployed` -> 3. `registered` -> 4. `active` -> 5. `scaled` (loop) -> 6. `decommissioned`

### Runner node pool lifecycle

1. `absent` -> 2. `created` -> 3. `labeled-tainted` -> 4. `schedulable-for-runners` -> 5. `autoscaling` -> 6. `scaled-to-minimum`

### Federation lifecycle

1. `absent` -> 2. `app-created` -> 3. `sp-created` -> 4. `credential-linked` -> 5. `roles-assigned` -> 6. `validated`

### Devcontainer image workflow lifecycle

1. `idle` -> 2. `triggered` -> 3. `auth-success` -> 4. `build-complete` -> 5. `push-complete` -> 6. `published`
