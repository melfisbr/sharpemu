param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$source = [IO.File]::ReadAllText($agc)

if ((Test-ContainsOrdinal -Text $source -Pattern 'SHARPEMU_TRACE_LABEL_PROVENANCE') -and
    (Test-ContainsOrdinal -Text $source -Pattern '[V73.4][LABEL]')) {
    Write-Host '[V73.4] Provenance instrumentation already installed; building current source.'
    Push-Location $root
    try {
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            throw ('SharpEmu.CLI build failed with exit code {0}.' -f $exit)
        }
    }
    finally {
        Pop-Location
    }

    Write-Host '[V73.4] SUCCESS (already instrumented)'
    Write-Host '[V73.4] Next: RUN_DEMONS_LABEL_PROVENANCE_V73_4.cmd'
    return
}

$baselineHash = 'AED440CE2307DE6103C28889303F41919D605F64B105A0D853B9E9AF4A948679'
$currentHash = (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
if ($currentHash -ne $baselineHash) {
    throw (
        '[V73.4] APPLY ERROR: AgcExports changed after precheck. Expected {0}; actual {1}.' -f
        $baselineHash,
        $currentHash)
}

$fields = [IO.File]::ReadAllText(
    (Join-Path $packageRoot 'evidence\AGC_FIELDS_FRAGMENT.cs.txt'))
$helpers = [IO.File]::ReadAllText(
    (Join-Path $packageRoot 'evidence\AGC_HELPERS_FRAGMENT.cs.txt'))

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $root ('.sharpemu-hotfix-backup\LabelProvenance_V73_4_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir 'AgcExports.cs'
Copy-Item -LiteralPath $agc -Destination $backup -Force

try {
    # 1. Fields immediately after existing AGC trace configuration.
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor '    // Drop a draw on an undecodable texture descriptor instead of substituting' `
        -Insertion $fields.TrimEnd() `
        -Name 'trace-fields'

    # 2. Helpers after CanonicalMemory and before register defaults.
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor '    private static readonly RegisterDefaultGroup[] PrimaryRegisterDefaults =' `
        -Insertion $helpers.TrimEnd() `
        -Name 'trace-helpers'

    # 3. Track future PM4 producer ranges after registration.
    $producerAnchor = '        void CompleteAndWake()'
    $producerInsert = @'
        TraceLabelProvenanceRangeV734(
            ctx.Memory,
            producerAddress,
            producerLength,
            $"pm4_producer_registered queue={state.QueueName} submission={state.ActiveSubmissionId} " +
            $"packet=0x{packetAddress:X16} name={debugName}");

'@
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor $producerAnchor `
        -Insertion $producerInsert.TrimEnd() `
        -Name 'pm4-producer-range'

    # 4. Trace actual Vulkan writeback ranges that overlap a producerless target.
    $writebackInsert = @'
        TraceLabelProvenanceRangeV734(
            canonicalMemory,
            start,
            length,
            "gpu_writeback");

'@
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor '        var observed = 0;' `
        -Insertion $writebackInsert.TrimEnd() `
        -Name 'gpu-writeback-range'

    # 5. Inspect every compute binding before the normal writable/writeback gate.
    $computeInsert = @'
        TraceComputeLabelCoverageV734(
            ctx.Memory,
            shaderAddress,
            state.QueueName,
            state.ActiveSubmissionId,
            globalMemoryBuffers);

'@
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor '        var candidateRanges = new List<(ulong Address, ulong Length)>();' `
        -Insertion $computeInsert.TrimEnd() `
        -Name 'compute-coverage'

    # 6. Register only waits that truly had no observed producer.
    $targetInsert = @'
        if (!hasObservedProducer)
        {
            RegisterLabelProvenanceTargetV734(
                canonicalWaitMemory,
                waiter,
                currentValue,
                hasObservedProducer);
        }

'@
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor '        var useGlobalVisibilityProbe =' `
        -Insertion $targetInsert.TrimEnd() `
        -Name 'producerless-wait-target'

    # 7. Decode address-bearing EVENT_WRITE 0x38/0x39 for provenance only.
    $eventInsert = @'
                if (_traceLabelProvenanceV734 &&
                    (eventTypeRaw & 0x100u) != 0 &&
                    length >= 4 &&
                    TryReadUInt64(ctx, currentAddress + 8, out var eventAddress))
                {
                    var targets = SnapshotLabelProvenanceTargetsV734(ctx.Memory);
                    if (targets.Length != 0)
                    {
                        TraceLabelProvenanceV734(
                            $"event_write_addressed type=0x{eventType:X2} " +
                            $"addr=0x{eventAddress:X16} queue={state.QueueName} " +
                            $"submission={state.ActiveSubmissionId} " +
                            $"packet=0x{currentAddress:X16}");
                        TraceLabelProvenanceRangeV734(
                            ctx.Memory,
                            eventAddress,
                            sizeof(ulong),
                            $"event_write type=0x{eventType:X2}");
                    }
                }

'@
    $source = Insert-BeforeUnique `
        -Text $source `
        -Anchor '                SubmitOrderedGpuSideEffect(' `
        -Insertion $eventInsert.TrimEnd() `
        -Name 'event-write-address'

    foreach ($marker in @(
        'SHARPEMU_TRACE_LABEL_PROVENANCE',
        '[V73.4][LABEL]',
        'TraceComputeLabelCoverageV734(',
        'pm4_producer_registered',
        '"gpu_writeback"',
        'RegisterLabelProvenanceTargetV734(',
        'event_write_addressed'
    )) {
        if (-not (Test-ContainsOrdinal -Text $source -Pattern $marker)) {
            throw ('[V73.4] Post-patch marker missing: {0}' -f $marker)
        }
    }

    [IO.File]::WriteAllText(
        $agc,
        $source,
        [Text.UTF8Encoding]::new($false))

    Write-Host '[V73.4] Installed bounded label-provenance instrumentation.'

    Push-Location $root
    try {
        Write-Host '[V73.4] Building SharpEmu.CLI Debug win-x64...'
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' `
            -c Debug `
            -r win-x64 `
            --nologo
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            throw ('SharpEmu.CLI build failed with exit code {0}.' -f $exit)
        }
    }
    finally {
        Pop-Location
    }

    Write-Host '[V73.4] SUCCESS'
    Write-Host ('[V73.4] Backup: {0}' -f $backupDir)
    Write-Host ('[V73.4] AgcExports_SHA256={0}' -f (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)
    Write-Host '[V73.4] Diagnostic only: no wait/label value is fabricated.'
    Write-Host '[V73.4] Next: RUN_DEMONS_LABEL_PROVENANCE_V73_4.cmd'
}
catch {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        Copy-Item -LiteralPath $backup -Destination $agc -Force
        Write-Host '[V73.4] AgcExports.cs restored.'
    }

    throw
}
