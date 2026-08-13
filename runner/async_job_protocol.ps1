[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare', 'Submit', 'Observe', 'Reconcile', 'Inspect')][string]$Action,
    [Parameter(Mandatory)][string]$RuntimeRoot,
    [string]$TaskId,
    [string]$ContractSha256,
    [string]$AdapterId,
    [string]$ProviderId,
    [string]$RequestSha256,
    [decimal]$BudgetCny,
    [string]$JobPath,
    [string]$ProviderJobRef,
    [string]$ObservationEventId,
    [string]$ObservedProviderId,
    [string]$ObservedIntentSha256,
    [string]$ObservedContractSha256,
    [ValidateSet('running', 'succeeded', 'failed', 'unknown')][string]$ProviderState,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
$canonicalRuntimeRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'))
if (-not [IO.Path]::GetFullPath($RuntimeRoot).Equals($canonicalRuntimeRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Provider Worker v0.2 must use the canonical RuntimeRoot: $canonicalRuntimeRoot"
}
$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\HermesAsyncJob.psm1'
Import-Module $module -Force
$parameters = @{}
foreach ($name in @('Action','RuntimeRoot','TaskId','ContractSha256','AdapterId','ProviderId','RequestSha256','BudgetCny','JobPath','ProviderJobRef','ObservationEventId','ObservedProviderId','ObservedIntentSha256','ObservedContractSha256','ProviderState')) {
    if ($PSBoundParameters.ContainsKey($name)) { $parameters[$name] = $PSBoundParameters[$name] }
}
$result = Invoke-HermesAsyncJob @parameters
if ($AsJson) { $result | ConvertTo-Json -Depth 100 } else { $result }
