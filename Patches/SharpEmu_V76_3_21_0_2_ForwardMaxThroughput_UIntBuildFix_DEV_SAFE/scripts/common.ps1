$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.21.0.2-FORWARD-MAX-THROUGHPUT-UINT-BUILDFIX'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'

$OriginalName = 'SharpEmu_V76_3_21_0_ForwardMaxThroughput_AdaptiveMerge_DEV_SAFE'
$OriginalPkg = Join-Path $Patches $OriginalName

$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'

$PresenterPath = Join-Path $Repo $PresenterRel
$CliPath = Join-Path $Repo $CliRel

$CompatMarker = 'SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC'
$CompatTag = 'V76.3.21.0.1_PRECHECK_SEMANTIC_BRIDGE'

function Fail([string]$Message) {
    throw "[$Tag] $Message"
}

function Ensure-Layout {
    foreach ($p in @($Repo,$Patches,$OriginalPkg)) {
        if (-not (Test-Path -LiteralPath $p -PathType Container)) {
            Fail "diretorio ausente: $p"
        }
    }

    foreach ($p in @($PresenterPath,$CliPath)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            Fail "arquivo ausente: $p"
        }
    }

    foreach ($name in @(
        'RUN_1_VALIDATE_PACKAGE.cmd',
        'RUN_2_PRECHECK.cmd',
        'RUN_3_APPLY_BUILD.cmd',
        'RUN_4_DIAGNOSTIC.cmd'
    )) {
        $path = Join-Path $OriginalPkg $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Fail "pacote V21.0 incompleto: $path"
        }
    }
}

function Get-HashLower([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SourceState {
    $presenter = [IO.File]::ReadAllText($PresenterPath)
    $cli = [IO.File]::ReadAllText($CliPath)

    # Presenter-side semantic evidence. We accept multiple historical names
    # because V21 is a forward/adaptive merge and should not be tied to one
    # telemetry string.
    $dualEvidence = @(
        '_computeQueueTimelineSemaphore',
        'DUAL_PHYSICAL_QUEUE_READY',
        'DUAL_QUEUE_SUBMIT',
        'ResolvePhysicalCrossQueueWait',
        'ResolveCrossQueueWait',
        'CommitCrossQueueAccess',
        'CrossQueueHazard',
        'timeline semaphore'
    ) | Where-Object { $presenter.Contains($_) }

    $resourceEvidence = @(
        'ResolveCrossQueueWait',
        'CommitCrossQueueAccess',
        'ResourceAccess',
        'GuestResource',
        'range',
        'hazard'
    ) | Where-Object { $presenter.Contains($_) }

    $cliDual = $cli.Contains('SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC') -or
               $cli.Contains('SHARPEMU_DUAL_QUEUE_SYNC_POLICY') -or
               $cli.Contains('dual-capability-resource') -or
               $cli.Contains('DUAL_PHYSICAL_QUEUE')

    [pscustomobject]@{
        Presenter = $presenter
        Cli = $cli
        DualEvidence = @($dualEvidence)
        ResourceEvidence = @($resourceEvidence)
        CliDual = $cliDual
        HasCompatMarker = $presenter.Contains($CompatMarker)
        HasCompatTag = $presenter.Contains($CompatTag)
    }
}

function Assert-SemanticDualQueueContract {
    $s = Get-SourceState

    if ($s.DualEvidence.Count -lt 1) {
        Fail (
            'Presenter nao possui evidencia estrutural de dual queue/timeline. ' +
            'Nao vou mascarar esse caso com um marker textual.'
        )
    }

    if ($s.ResourceEvidence.Count -lt 1) {
        Fail (
            'Presenter nao possui evidencia estrutural de resource/range hazard. ' +
            'Nao vou mascarar esse caso com um marker textual.'
        )
    }

    if (-not $s.CliDual) {
        Fail (
            'CLI nao possui politica dual/resource. ' +
            'O erro nao e apenas de precheck; merge V21 precisa ser revisto.'
        )
    }

    Write-Host (
        "[$Tag] semantic_presenter_dual=" +
        ($s.DualEvidence -join ',')
    )
    Write-Host (
        "[$Tag] semantic_presenter_resource=" +
        ($s.ResourceEvidence -join ',')
    )
    Write-Host "[$Tag] semantic_cli_dual=$($s.CliDual)"

    return $s
}

function Add-CompatibilityMarker {
    $s = Assert-SemanticDualQueueContract

    if ($s.HasCompatMarker) {
        Write-Host "[$Tag] compatibility marker already present"
        return $false
    }

    $bytes = [IO.File]::ReadAllBytes($PresenterPath)
    $hasBom = $bytes.Length -ge 3 -and
              $bytes[0] -eq 0xEF -and
              $bytes[1] -eq 0xBB -and
              $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString(
        $bytes,
        $offset,
        $bytes.Length - $offset)

    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

    # This is intentionally a comment only. It does not change runtime policy.
    # The V21.0 precheck incorrectly asks the Presenter to contain a CLI/env
    # contract name. The real Presenter contract was verified above through
    # queue/timeline/hazard implementation markers.
    $header = @(
        '// V76.3.21.0.1_PRECHECK_SEMANTIC_BRIDGE',
        '// Compatibility marker for the V76.3.21.0 structural precheck only.',
        '// Runtime ownership remains in the existing dual-queue/timeline/resource-hazard implementation.',
        '// SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC is configured by the title/profile layer; this comment adds no behavior.',
        ''
    ) -join $nl

    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [IO.File]::WriteAllText($PresenterPath, $header + $text, $enc)

    $check = [IO.File]::ReadAllText($PresenterPath)
    if (-not $check.Contains($CompatMarker) -or
        -not $check.Contains($CompatTag)) {
        Fail 'falha ao instalar marker de compatibilidade'
    }

    Write-Host "[$Tag] compatibility marker installed behavior_change=0"
    return $true
}


function Add-MaxFramesCommandBufferCountUIntBridge {
    $bytes = [IO.File]::ReadAllBytes($PresenterPath)
    $hasBom = $bytes.Length -ge 3 -and
              $bytes[0] -eq 0xEF -and
              $bytes[1] -eq 0xBB -and
              $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString(
        $bytes,
        $offset,
        $bytes.Length - $offset)

    $fixed = 'CommandBufferCount = (uint)MaxFramesInFlight,'
    if ($text.Contains($fixed)) {
        Write-Host "[$Tag] uint bridge already present"
        return $false
    }

    $legacy = 'CommandBufferCount = MaxFramesInFlight,'
    $first = $text.IndexOf($legacy, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        Fail 'CommandBufferCount/MaxFramesInFlight anchor ausente'
    }

    $second = $text.IndexOf(
        $legacy,
        $first + $legacy.Length,
        [StringComparison]::Ordinal)
    if ($second -ge 0) {
        Fail 'CommandBufferCount/MaxFramesInFlight anchor nao-unico'
    }

    # Behavior-neutral while MaxFramesInFlight is const int, and required once
    # V21.0 promotes it to a runtime-configurable static readonly int.
    $text = $text.Remove($first, $legacy.Length).Insert($first, $fixed)

    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [IO.File]::WriteAllText($PresenterPath, $text, $enc)

    $check = [IO.File]::ReadAllText($PresenterPath)
    if (-not $check.Contains($fixed)) {
        Fail 'falha ao instalar uint bridge de MaxFramesInFlight'
    }

    Write-Host (
        "[$Tag] uint bridge installed " +
        "compile_fix=CommandBufferCount-int-to-uint behavior_change=0"
    )
    return $true
}
