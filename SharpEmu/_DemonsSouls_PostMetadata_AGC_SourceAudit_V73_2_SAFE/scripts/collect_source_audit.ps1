param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_2_POSTMETADATA_AGC_SOURCE_AUDIT_{0}' -f $stamp)
$sources = Join-Path $out 'sources'
$windows = Join-Path $out 'source_windows'
New-Item -ItemType Directory -Force -Path $sources | Out-Null
New-Item -ItemType Directory -Force -Path $windows | Out-Null

$targetRelative = @(
    'src\SharpEmu.Core\Loader\SelfLoader.cs',
    'src\SharpEmu.Libs\Agc\AgcExports.cs',
    'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
)

$manifestLines = New-Object System.Collections.Generic.List[string]

foreach ($relative in $targetRelative) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $manifestLines.Add(('MISSING {0}' -f $relative))
        continue
    }

    $destination = Join-Path $sources $relative
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force

    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $manifestLines.Add(('{0}  {1}' -f $hash, $relative))
}

$patterns = @(
    'canonical-empty-fastpath',
    'TryReadComputeDispatch',
    'RejectComputeDispatch',
    'HandleSubmittedIndirectDimsWait',
    '_indirectDimsExpired',
    'dispatch_indirect',
    'wait_suspended',
    'TraceWaitProducerState',
    'RegisterLabelProducer',
    'CompleteLabelProducer',
    'RecordProducedLabelsInRange',
    'RecordProduced(',
    'producerCompletionAction',
    'EVENT_FASTPATH',
    'ItEventWrite',
    'event_write',
    'SubmitOrderedGpuSideEffect',
    'SubmitOrderedGuestAction',
    'guest_queue_backpressure',
    'ordered_action_fence_wait',
    'rt_sampled',
    'IsGpuGuestImageAvailable',
    'global_writeback'
)

$searchRoot = Join-Path $root 'src'
$csFiles = @(Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue)

$matchRows = New-Object System.Collections.Generic.List[object]
$discoveredPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

foreach ($file in $csFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)

    foreach ($pattern in $patterns) {
        if ($text.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        [void]$discoveredPaths.Add($file.FullName)

        $lines = [IO.File]::ReadAllLines($file.FullName)
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i].IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                continue
            }

            $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
            $row = New-Object PSObject
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'File' -Value $relative
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'Line' -Value ($i + 1)
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'Pattern' -Value $pattern
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'Text' -Value $lines[$i].Trim()
            $matchRows.Add($row)
        }
    }
}

$matchRows |
    Sort-Object File, Line, Pattern |
    Export-Csv -LiteralPath (Join-Path $out 'SOURCE_SYMBOL_MATCHES.csv') -NoTypeInformation -Encoding UTF8

# Copy every discovered file, capped to 40 to keep the evidence package bounded.
$discovered = @($discoveredPaths | Sort-Object)
$copied = 0
foreach ($source in $discovered) {
    if ($copied -ge 40) {
        break
    }

    $relative = $source.Substring($root.Length).TrimStart('\','/')
    $destination = Join-Path $sources ('discovered\' + $relative)
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force

    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $manifestLines.Add(('{0}  discovered\{1}' -f $hash, $relative))
    $copied++
}

# Produce readable context windows around the important source markers.
$windowTargets = @(
    (Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'),
    (Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'),
    (Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
)

foreach ($source in $windowTargets) {
    $sourceLines = [IO.File]::ReadAllLines($source)
    $outputLines = New-Object System.Collections.Generic.List[string]

    foreach ($pattern in $patterns) {
        for ($i = 0; $i -lt $sourceLines.Length; $i++) {
            if ($sourceLines[$i].IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                continue
            }

            $first = [Math]::Max(0, $i - 35)
            $last = [Math]::Min($sourceLines.Length - 1, $i + 55)
            $outputLines.Add(
                ('===== pattern={0} line={1} file={2} =====' -f
                    $pattern,
                    ($i + 1),
                    [IO.Path]::GetFileName($source)))

            for ($j = $first; $j -le $last; $j++) {
                $outputLines.Add(('{0,7}: {1}' -f ($j + 1), $sourceLines[$j]))
            }

            $outputLines.Add('')
        }
    }

    $windowName = [IO.Path]::GetFileNameWithoutExtension($source) + '_WINDOWS.txt'
    Write-Utf8Lines -Path (Join-Path $windows $windowName) -Lines $outputLines
}

# Current semantic marker matrix.
$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$waitRegistry = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$presenter = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$agcText = [IO.File]::ReadAllText($agc)
$waitText = [IO.File]::ReadAllText($waitRegistry)
$presenterText = [IO.File]::ReadAllText($presenter)

$state = New-Object System.Collections.Generic.List[string]
$state.Add('version=73.2')
$state.Add(('canonical_empty_fastpath={0}' -f (Test-ContainsOrdinal -Text $agcText -Pattern 'canonical-empty-fastpath')))
$state.Add(('record_produced_range={0}' -f (Test-ContainsOrdinal -Text $agcText -Pattern 'RecordProducedLabelsInRange')))
$state.Add(('producer_completion_action={0}' -f (Test-ContainsOrdinal -Text $agcText -Pattern 'producerCompletionAction')))
$state.Add(('wait_record_produced={0}' -f (Test-ContainsOrdinal -Text $waitText -Pattern 'RecordProduced(')))
$state.Add(('wait_canonicalize={0}' -f (Test-ContainsOrdinal -Text $waitText -Pattern 'Canonicalize(')))
$state.Add(('indirect_expired={0}' -f (Test-ContainsOrdinal -Text $agcText -Pattern '_indirectDimsExpired')))
$state.Add(('ordered_gpu_side_effect={0}' -f (Test-ContainsOrdinal -Text $agcText -Pattern 'SubmitOrderedGpuSideEffect')))
$state.Add(('event_fastpath={0}' -f (Test-ContainsOrdinal -Text $agcText -Pattern 'EVENT_FASTPATH')))
$state.Add(('presenter_backpressure={0}' -f (Test-ContainsOrdinal -Text $presenterText -Pattern 'guest_queue_backpressure')))
$state.Add(('presenter_ordered_wait={0}' -f (Test-ContainsOrdinal -Text $presenterText -Pattern 'ordered_action_fence_wait')))
$state.Add(('discovered_source_files={0}' -f $discovered.Count))
$state.Add(('discovered_source_files_copied={0}' -f $copied))
Write-Utf8Lines -Path (Join-Path $out 'SOURCE_STATE.txt') -Lines $state

Write-Utf8Lines -Path (Join-Path $out 'SOURCE_SHA256.txt') -Lines $manifestLines

# Preserve the V73.1.1 runtime evidence in this source audit.
Copy-Item -LiteralPath (Join-Path $packageRoot 'evidence\V73_1_1_RUNTIME_EVIDENCE.txt') `
    -Destination (Join-Path $out 'V73_1_1_RUNTIME_EVIDENCE.txt') -Force
Copy-Item -LiteralPath (Join-Path $packageRoot 'evidence\V73_1_1_SUMMARY.txt') `
    -Destination (Join-Path $out 'V73_1_1_SUMMARY.txt') -Force

# Git state is diagnostic only; warnings/errors do not abort source collection.
Push-Location $root
try {
    try {
        (& git status --short 2>&1) |
            Set-Content -LiteralPath (Join-Path $out 'GIT_STATUS.txt') -Encoding UTF8
    }
    catch {
        ('git status failed: {0}' -f $_.Exception.Message) |
            Set-Content -LiteralPath (Join-Path $out 'GIT_STATUS.txt') -Encoding UTF8
    }

    try {
        (& git diff -- 'src/SharpEmu.Libs/Agc/AgcExports.cs' `
                      'src/SharpEmu.Libs/Agc/GpuWaitRegistry.cs' `
                      'src/SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs' 2>&1) |
            Set-Content -LiteralPath (Join-Path $out 'AGC_PRESENTER_GIT_DIFF.txt') -Encoding UTF8
    }
    catch {
        ('git diff failed: {0}' -f $_.Exception.Message) |
            Set-Content -LiteralPath (Join-Path $out 'AGC_PRESENTER_GIT_DIFF.txt') -Encoding UTF8
    }
}
finally {
    Pop-Location
}

$summaryLines = @(
    'version=73.2',
    'purpose=collect exact current AGC/wait/presenter source after successful Gen5 metadata integration',
    'source_mutation=False',
    'game_started=False',
    'known_runtime_metadata=53 libraries / 49 modules',
    'known_runtime_unresolved_imports=0',
    'known_runtime_wait_suspended=7',
    'known_runtime_dispatch_reject=43',
    'known_runtime_backpressure=8',
    'known_runtime_device_lost=0',
    ('agc_sha256={0}' -f (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash),
    ('gpu_wait_registry_sha256={0}' -f (Get-FileHash -LiteralPath $waitRegistry -Algorithm SHA256).Hash),
    ('presenter_sha256={0}' -f (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)
)
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summaryLines

$zipPath = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath -Force

Write-Host ('[V73.2] RESULT: {0}' -f $zipPath)
Write-Host ('[V73.2] Discovered source files: {0}; copied: {1}' -f $discovered.Count, $copied)
Write-Host '[V73.2] No game was started and no repository source was modified.'
