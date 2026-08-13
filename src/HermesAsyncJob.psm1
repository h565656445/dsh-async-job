Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$jsonModule = Join-Path $PSScriptRoot 'HermesJsonProjection.psm1'
$ledgerModule = Join-Path $PSScriptRoot 'HermesLedgerTransaction.psm1'
$intentSchema = Join-Path $projectRoot 'schemas\schema_registry\v0.2\async-job-intent.schema.json'
$eventSchema = Join-Path $projectRoot 'schemas\schema_registry\v0.2\async-job-event.schema.json'
Import-Module $jsonModule -Force
Import-Module $ledgerModule -Force

function Get-HermesAsyncSha256 {
    param([Parameter(Mandatory)][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))
}

function Get-HermesAsyncSchemaIdentity {
    param([Parameter(Mandatory)][string]$SchemaId, [Parameter(Mandatory)][string]$SchemaPath)
    [ordered]@{
        schema_id = $SchemaId
        version = '0.2'
        sha256 = (Get-FileHash -LiteralPath $SchemaPath -Algorithm SHA256).Hash
    }
}

function Assert-HermesAsyncRoot {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Async job path cannot traverse a reparse point.' }
        }
        $next = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($next) -or $next -eq $cursor) { break }
        $cursor = $next
    }
    $full
}

function Get-HermesAsyncJobFiles {
    param([Parameter(Mandatory)][string]$JobPath, [Parameter(Mandatory)][string]$RuntimeRoot)
    $full = Assert-HermesAsyncRoot $JobPath
    $root = (Assert-HermesAsyncRoot $RuntimeRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Async job path is outside the supplied RuntimeRoot authority.'
    }
    [pscustomobject]@{
        job_path = $full
        intent_path = Join-Path $full 'intent.json'
        ledger_path = Join-Path $full 'job_ledger.jsonl'
    }
}

function Read-HermesAsyncIntent {
    param([Parameter(Mandatory)]$Files)
    if (-not (Test-Path -LiteralPath $Files.intent_path -PathType Leaf)) { throw "Async job intent not found: $($Files.intent_path)" }
    $snapshot = Get-HermesJsonSnapshot -Path $Files.intent_path -SchemaPath $intentSchema
    [pscustomobject]@{ document = $snapshot.document; sha256 = $snapshot.token_sha256 }
}

function Get-HermesAsyncEvents {
    param([Parameter(Mandatory)]$Files)
    $snapshot = Get-HermesLedgerSnapshot -LedgerPath $Files.ledger_path -AllowMissing
    $events = @(
        foreach ($line in @($snapshot.lines)) {
            if (-not ($line | Test-Json -SchemaFile $eventSchema -ErrorAction Stop)) { throw 'Async job Ledger contains an invalid event.' }
            $line | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        }
    )
    [pscustomobject]@{ snapshot = $snapshot; events = $events }
}

function Get-HermesAsyncState {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Events)
    if ($Events.Count -eq 0) { return $null }
    [string]$Events[-1].to_state
}

function New-HermesAsyncEvent {
    param(
        [Parameter(Mandatory)]$Intent,
        [Parameter(Mandatory)][string]$IntentSha256,
        [Parameter(Mandatory)][int]$Sequence,
        [Parameter(Mandatory)][string]$EventType,
        $FromState,
        [Parameter(Mandatory)][string]$ToState,
        [Parameter(Mandatory)][bool]$TrustedSource,
        [Parameter(Mandatory)][bool]$ChangesState,
        [string]$ProviderJobRef,
        [string]$ObservationEventId,
        [string]$ObservedProviderId,
        [string]$ObservedIntentSha256,
        [string]$ObservedContractSha256,
        [string]$ObservedState,
        [Parameter(Mandatory)][string]$Reason
    )
    $eventSeed = '{0}|{1}|{2}|{3}|{4}' -f $Intent.async_job_id, $Sequence, $EventType, $ObservationEventId, $ToState
    [ordered]@{
        schema_identity = Get-HermesAsyncSchemaIdentity -SchemaId 'hermes.async_job_event' -SchemaPath $eventSchema
        sequence = $Sequence
        event_id = 'async-event-' + (Get-HermesAsyncSha256 $eventSeed).Substring(0, 16).ToLowerInvariant()
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        event_type = $EventType
        async_job_id = [string]$Intent.async_job_id
        intent_sha256 = $IntentSha256
        contract_sha256 = [string]$Intent.contract_sha256
        provider_id = [string]$Intent.provider_id
        provider_job_ref = if ([string]::IsNullOrWhiteSpace($ProviderJobRef)) { $null } else { $ProviderJobRef }
        observation_event_id = if ([string]::IsNullOrWhiteSpace($ObservationEventId)) { $null } else { $ObservationEventId }
        observed_provider_id = if ([string]::IsNullOrWhiteSpace($ObservedProviderId)) { $null } else { $ObservedProviderId }
        observed_intent_sha256 = if ([string]$ObservedIntentSha256 -match '^[A-Fa-f0-9]{64}$') { $ObservedIntentSha256.ToUpperInvariant() } else { $null }
        observed_contract_sha256 = if ([string]$ObservedContractSha256 -match '^[A-Fa-f0-9]{64}$') { $ObservedContractSha256.ToUpperInvariant() } else { $null }
        observed_state = if ([string]::IsNullOrWhiteSpace($ObservedState)) { $null } else { $ObservedState }
        trusted_source = $TrustedSource
        changes_state = $ChangesState
        from_state = $FromState
        to_state = $ToState
        reason = $Reason
        hermes_completed = $false
    }
}

function Add-HermesAsyncEvent {
    param([Parameter(Mandatory)]$Files, [Parameter(Mandatory)]$Event, [Parameter(Mandatory)]$LedgerSnapshot)
    $line = $Event | ConvertTo-Json -Compress -Depth 100
    if (-not ($line | Test-Json -SchemaFile $eventSchema -ErrorAction Stop)) { throw 'Async job event failed schema validation.' }
    Add-HermesLedgerRecord -LedgerPath $Files.ledger_path -ExpectedToken $LedgerSnapshot.token_sha256 -JsonLine $line
}

function ConvertTo-HermesAsyncResult {
    param(
        [Parameter(Mandatory)]$Files,
        [Parameter(Mandatory)]$IntentRead,
        [Parameter(Mandatory)][string]$State,
        [string]$EventType,
        [bool]$StateChanged = $false,
        [bool]$Duplicate = $false,
        [bool]$CandidateOnly = $false
    )
    [pscustomobject][ordered]@{
        async_job_id = [string]$IntentRead.document.async_job_id
        job_path = $Files.job_path
        intent_sha256 = $IntentRead.sha256
        state = $State
        event_type = $EventType
        state_changed = $StateChanged
        duplicate_observation = $Duplicate
        candidate_only = $CandidateOnly
        hermes_completed = $false
    }
}

function Invoke-HermesAsyncPrepare {
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ContractSha256,
        [Parameter(Mandatory)][string]$AdapterId,
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)][string]$RequestSha256,
        [Parameter(Mandatory)][decimal]$BudgetCny
    )
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$') { throw 'Async job task_id is not path-safe.' }
    foreach ($hash in @($ContractSha256, $RequestSha256)) {
        if ($hash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Async job hash binding is invalid.' }
    }
    if ($ProviderId -notmatch '^[a-z0-9][a-z0-9-]{2,63}$') { throw 'Async job provider_id is invalid.' }
    if ($BudgetCny -lt 0) { throw 'Async job budget cannot be negative.' }
    $root = Assert-HermesAsyncRoot $RuntimeRoot
    $idempotency = Get-HermesAsyncSha256 ('{0}|{1}|{2}|{3}|{4}' -f $TaskId, $ContractSha256.ToUpperInvariant(), $AdapterId, $ProviderId, $RequestSha256.ToUpperInvariant())
    $asyncJobId = 'async-job-' + $idempotency.Substring(0, 16).ToLowerInvariant()
    $jobPath = Join-Path $root ("tasks\$TaskId\async_jobs\$asyncJobId")
    $files = Get-HermesAsyncJobFiles -JobPath $jobPath -RuntimeRoot $root
    $null = New-Item -ItemType Directory -Path $files.job_path -Force

    if (Test-Path -LiteralPath $files.intent_path -PathType Leaf) {
        $existing = Read-HermesAsyncIntent $files
        if ([string]$existing.document.idempotency_key -cne $idempotency) { throw 'Async job immutable intent conflict.' }
        $eventRead = Get-HermesAsyncEvents $files
        if ($eventRead.events.Count -eq 0) {
            $event = New-HermesAsyncEvent -Intent $existing.document -IntentSha256 $existing.sha256 -Sequence 1 -EventType 'job_prepared' -FromState $null -ToState 'prepared' -TrustedSource $true -ChangesState $true -Reason 'Hermes recovered the initial event for an existing immutable async job intent.'
            $null = Add-HermesAsyncEvent -Files $files -Event $event -LedgerSnapshot $eventRead.snapshot
            return ConvertTo-HermesAsyncResult -Files $files -IntentRead $existing -State 'prepared' -EventType 'job_prepared' -StateChanged $true
        }
        return ConvertTo-HermesAsyncResult -Files $files -IntentRead $existing -State (Get-HermesAsyncState @($eventRead.events)) -EventType 'job_prepared'
    }

    $intent = [ordered]@{
        schema_identity = Get-HermesAsyncSchemaIdentity -SchemaId 'hermes.async_job_intent' -SchemaPath $intentSchema
        async_job_id = $asyncJobId
        task_id = $TaskId
        contract_sha256 = $ContractSha256.ToUpperInvariant()
        adapter_id = $AdapterId
        provider_id = $ProviderId
        idempotency_key = $idempotency
        request_sha256 = $RequestSha256.ToUpperInvariant()
        budget_cny = $BudgetCny
        created_at = [DateTimeOffset]::UtcNow.ToString('o')
        state = 'prepared'
        third_party_success_is_hermes_completion = $false
    }
    $missing = Get-HermesJsonSnapshot -Path $files.intent_path -AllowMissing
    $null = Set-HermesJsonProjection -Path $files.intent_path -Document $intent -ExpectedToken $missing.token_sha256 -SchemaPath $intentSchema
    $intentRead = Read-HermesAsyncIntent $files
    $ledger = Get-HermesAsyncEvents $files
    $event = New-HermesAsyncEvent -Intent $intentRead.document -IntentSha256 $intentRead.sha256 -Sequence 1 -EventType 'job_prepared' -FromState $null -ToState 'prepared' -TrustedSource $true -ChangesState $true -Reason 'Hermes wrote the immutable async job intent.'
    $null = Add-HermesAsyncEvent -Files $files -Event $event -LedgerSnapshot $ledger.snapshot
    ConvertTo-HermesAsyncResult -Files $files -IntentRead $intentRead -State 'prepared' -EventType 'job_prepared' -StateChanged $true
}

function Invoke-HermesAsyncSubmit {
    param([Parameter(Mandatory)][string]$RuntimeRoot, [Parameter(Mandatory)][string]$JobPath, [Parameter(Mandatory)][string]$ProviderJobRef)
    $files = Get-HermesAsyncJobFiles -JobPath $JobPath -RuntimeRoot $RuntimeRoot
    $intentRead = Read-HermesAsyncIntent $files
    $ledger = Get-HermesAsyncEvents $files
    $state = Get-HermesAsyncState @($ledger.events)
    if ($state -ne 'prepared') { throw "Async job Submit requires prepared state, actual: $state" }
    if ([string]::IsNullOrWhiteSpace($ProviderJobRef)) { throw 'Provider Adapter Submit must return provider_job_ref.' }
    $event = New-HermesAsyncEvent -Intent $intentRead.document -IntentSha256 $intentRead.sha256 -Sequence ($ledger.events.Count + 1) -EventType 'job_submitted' -FromState $state -ToState 'submitted' -TrustedSource $true -ChangesState $true -ProviderJobRef $ProviderJobRef -Reason 'AsyncJob accepted the internal Provider Adapter Submit receipt.'
    $null = Add-HermesAsyncEvent -Files $files -Event $event -LedgerSnapshot $ledger.snapshot
    ConvertTo-HermesAsyncResult -Files $files -IntentRead $intentRead -State 'submitted' -EventType 'job_submitted' -StateChanged $true
}

function Invoke-HermesAsyncObserve {
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$JobPath,
        [Parameter(Mandatory)][string]$ObservationEventId,
        [string]$ObservedProviderId,
        [string]$ObservedIntentSha256,
        [string]$ObservedContractSha256,
        [Parameter(Mandatory)][ValidateSet('running', 'succeeded', 'failed', 'unknown')][string]$ProviderState,
        [string]$ProviderJobRef
    )
    $files = Get-HermesAsyncJobFiles -JobPath $JobPath -RuntimeRoot $RuntimeRoot
    $intentRead = Read-HermesAsyncIntent $files
    $ledger = Get-HermesAsyncEvents $files
    $state = Get-HermesAsyncState @($ledger.events)
    $prior = @($ledger.events | Where-Object { [string]$_.observation_event_id -ceq $ObservationEventId })
    if ($prior.Count -gt 0) {
        $normalizedIntentSha256 = if ([string]$ObservedIntentSha256 -match '^[A-Fa-f0-9]{64}$') { $ObservedIntentSha256.ToUpperInvariant() } else { $null }
        $normalizedContractSha256 = if ([string]$ObservedContractSha256 -match '^[A-Fa-f0-9]{64}$') { $ObservedContractSha256.ToUpperInvariant() } else { $null }
        $normalizedProviderId = if ([string]::IsNullOrWhiteSpace($ObservedProviderId)) { $null } else { $ObservedProviderId }
        if ($prior.Count -ne 1 -or
            [bool]$prior[0].trusted_source -ne $false -or
            [string]$prior[0].observed_provider_id -cne [string]$normalizedProviderId -or
            [string]$prior[0].observed_intent_sha256 -cne [string]$normalizedIntentSha256 -or
            [string]$prior[0].observed_contract_sha256 -cne [string]$normalizedContractSha256 -or
            [string]$prior[0].observed_state -cne $ProviderState -or
            [string]$prior[0].provider_job_ref -cne $ProviderJobRef) {
            throw 'Async job observation event id was replayed with conflicting content.'
        }
        return ConvertTo-HermesAsyncResult -Files $files -IntentRead $intentRead -State $state -EventType ([string]$prior[0].event_type) -Duplicate $true
    }
    $event = New-HermesAsyncEvent -Intent $intentRead.document -IntentSha256 $intentRead.sha256 -Sequence ($ledger.events.Count + 1) -EventType 'security_callback_rejected' -FromState $state -ToState $state -TrustedSource $false -ChangesState $false -ProviderJobRef $ProviderJobRef -ObservationEventId $ObservationEventId -ObservedProviderId $ObservedProviderId -ObservedIntentSha256 $ObservedIntentSha256 -ObservedContractSha256 $ObservedContractSha256 -ObservedState $ProviderState -Reason 'No signed callback or active polling trust verifier is registered in protocol v0.2; observation evidence was retained without changing state.'
    $null = Add-HermesAsyncEvent -Files $files -Event $event -LedgerSnapshot $ledger.snapshot
    ConvertTo-HermesAsyncResult -Files $files -IntentRead $intentRead -State $state -EventType 'security_callback_rejected' -StateChanged $false
}

function Invoke-HermesAsyncReconcile {
    param([Parameter(Mandatory)][string]$RuntimeRoot, [Parameter(Mandatory)][string]$JobPath)
    $files = Get-HermesAsyncJobFiles -JobPath $JobPath -RuntimeRoot $RuntimeRoot
    $intentRead = Read-HermesAsyncIntent $files
    $ledger = Get-HermesAsyncEvents $files
    $state = Get-HermesAsyncState @($ledger.events)
    if ($state -notin @('provider_succeeded', 'provider_failed', 'outcome_unknown')) { throw "Async job Reconcile requires a Provider terminal or unknown state, actual: $state" }
    $providerJobRef = [string](@($ledger.events | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.provider_job_ref) }) | Select-Object -Last 1).provider_job_ref
    $event = New-HermesAsyncEvent -Intent $intentRead.document -IntentSha256 $intentRead.sha256 -Sequence ($ledger.events.Count + 1) -EventType 'job_reconciled' -FromState $state -ToState 'reconciled' -TrustedSource $true -ChangesState $true -ProviderJobRef $providerJobRef -Reason 'AsyncJob reconciled Provider evidence as candidate-only output.'
    $null = Add-HermesAsyncEvent -Files $files -Event $event -LedgerSnapshot $ledger.snapshot
    ConvertTo-HermesAsyncResult -Files $files -IntentRead $intentRead -State 'reconciled' -EventType 'job_reconciled' -StateChanged $true -CandidateOnly $true
}

function Invoke-HermesAsyncInspect {
    param([Parameter(Mandatory)][string]$RuntimeRoot, [Parameter(Mandatory)][string]$JobPath)
    $files = Get-HermesAsyncJobFiles -JobPath $JobPath -RuntimeRoot $RuntimeRoot
    $intentRead = Read-HermesAsyncIntent $files
    $ledger = Get-HermesAsyncEvents $files
    ConvertTo-HermesAsyncResult -Files $files -IntentRead $intentRead -State (Get-HermesAsyncState @($ledger.events))
}

function Invoke-HermesAsyncJob {
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
        [ValidateSet('running', 'succeeded', 'failed', 'unknown')][string]$ProviderState
    )
    switch ($Action) {
        'Prepare' { Invoke-HermesAsyncPrepare -RuntimeRoot $RuntimeRoot -TaskId $TaskId -ContractSha256 $ContractSha256 -AdapterId $AdapterId -ProviderId $ProviderId -RequestSha256 $RequestSha256 -BudgetCny $BudgetCny }
        'Submit' { Invoke-HermesAsyncSubmit -RuntimeRoot $RuntimeRoot -JobPath $JobPath -ProviderJobRef $ProviderJobRef }
        'Observe' { Invoke-HermesAsyncObserve -RuntimeRoot $RuntimeRoot -JobPath $JobPath -ObservationEventId $ObservationEventId -ObservedProviderId $ObservedProviderId -ObservedIntentSha256 $ObservedIntentSha256 -ObservedContractSha256 $ObservedContractSha256 -ProviderState $ProviderState -ProviderJobRef $ProviderJobRef }
        'Reconcile' { Invoke-HermesAsyncReconcile -RuntimeRoot $RuntimeRoot -JobPath $JobPath }
        'Inspect' { Invoke-HermesAsyncInspect -RuntimeRoot $RuntimeRoot -JobPath $JobPath }
    }
}

Export-ModuleMember -Function 'Invoke-HermesAsyncJob'
