Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Tag = '[V74.0.75]'
$script:PackageName = 'SharpEmu_V74_0_75_ProcessingFlow_TextureWaitWake_SAFE'
$script:PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:GpuTypesRel = 'src\SharpEmu.Libs\Gpu\GuestGpuTypes.cs'
$script:PresenterMarker = 'SHARPEMU_V74_0_75_PRE_SNAPSHOT_SAMPLER_ALIAS'
$script:AgcMarker = 'SHARPEMU_V74_0_75_PRODUCER_WAKE_DRAIN'
$script:AllocMarker = 'SHARPEMU_V74_0_75_UNINITIALIZED_TEXTURE_SNAPSHOT'

function Resolve-SharpEmuRepo([string]$RequestedRoot) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) { $candidates.Add($RequestedRoot) }
    $packageParent = Split-Path -Parent $script:PackageRoot
    if (-not [string]::IsNullOrWhiteSpace($packageParent)) {
        $candidates.Add((Split-Path -Parent $packageParent))
    }
    $candidates.Add((Get-Location).Path)
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try { $full = [System.IO.Path]::GetFullPath($candidate) } catch { continue }
        if (Test-Path -LiteralPath (Join-Path $full $script:PresenterRel)) { return $full }
        if ((Split-Path -Leaf $full) -ieq 'Patches') {
            $parent = Split-Path -Parent $full
            if (Test-Path -LiteralPath (Join-Path $parent $script:PresenterRel)) { return $parent }
        }
    }
    throw "$script:Tag Nao foi possivel localizar a raiz do SharpEmu."
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Get-SourceState([string]$RepoRoot) {
    $presenter = Join-Path $RepoRoot $script:PresenterRel
    $agc = Join-Path $RepoRoot $script:AgcRel
    $gpuTypes = Join-Path $RepoRoot $script:GpuTypesRel
    foreach ($path in @($presenter, $agc, $gpuTypes)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "$script:Tag Arquivo ausente: $path" }
    }

    $p = Get-Text $presenter
    $a = Get-Text $agc
    $g = Get-Text $gpuTypes

    foreach ($needle in @(
        '_cachedTextureIdentities',
        'internal static bool IsTextureContentCached',
        'SHARPEMU_V74_0_73_TEXTURE_RESOURCE_HOT_PATH')) {
        if (-not $p.Contains($needle)) { throw "$script:Tag Presenter incompativel: ausente '$needle'." }
    }
    foreach ($needle in @(
        'internal readonly record struct TextureContentIdentity(',
        'GuestSampler Sampler',
        'ulong MetadataAddress',
        'uint DescriptorFlags',
        'uint BcSwizzle',
        'bool HasExtendedDescriptor')) {
        if (-not $g.Contains($needle)) { throw "$script:Tag TextureContentIdentity incompativel: ausente '$needle'." }
    }
    foreach ($needle in @(
        'private static void RequestResumableDcbDrain',
        'private static void SignalGpuWaitMonitor',
        'private static void EnsureGpuWaitMonitor',
        'PendingDrainContext',
        'TryCreateGuestDrawTexture',
        'DrainResumableDcbs')) {
        if (-not $a.Contains($needle)) { throw "$script:Tag AGC incompativel: ausente '$needle'." }
    }

    $presenterOwn = $p.Contains($script:PresenterMarker) -and $p.Contains('IsExactTextureContentCachedV74075')
    $presenterExisting = $p.Contains('SHARPEMU_V74_0_56_33_2_PRE_SNAPSHOT_SAMPLER_ALIAS_STRUCTURAL') -and $p.Contains('IsExactTextureContentCachedV74056332')
    $presenterOld = ($p.Contains('SHARPEMU_V74_0_56_33_PRE_SNAPSHOT_SAMPLER_ALIAS') -or $p.Contains('IsExactTextureContentCachedV7405633')) -and -not $presenterExisting
    if ($presenterOld) {
        throw "$script:Tag Detectada uma V74.0.56.33 antiga/parcial no presenter. Restaure essa tentativa antes de aplicar V74.0.75."
    }

    $agcOwn = $a.Contains($script:AgcMarker) -and
              $a.Contains('_v74075ProducerWakeDrainCount') -and
              $a.Contains($script:AllocMarker)

    $presenterState = if ($presenterOwn) { 'v74075' } elseif ($presenterExisting) { 'v74056332-compatible' } else { 'needs-patch' }
    $agcState = if ($agcOwn) { 'v74075' } else { 'needs-patch' }

    return [pscustomobject]@{
        PresenterState = $presenterState
        AgcState = $agcState
        PresenterSha = Get-Sha256 $presenter
        AgcSha = Get-Sha256 $agc
    }
}

function Apply-PresenterAliasPatch([string]$TargetPath) {
    $text = Get-Text $TargetPath
    if ($text.Contains($script:PresenterMarker) -or
        ($text.Contains('SHARPEMU_V74_0_56_33_2_PRE_SNAPSHOT_SAMPLER_ALIAS_STRUCTURAL') -and
         $text.Contains('IsExactTextureContentCachedV74056332'))) {
        return $false
    }

    $pattern = '(?m)^(?<indent>[ \t]*)internal\s+static\s+bool\s+IsTextureContentCached\s*\(\s*in\s+TextureContentIdentity\s+identity\s*\)'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) { throw "$script:Tag Presenter anchor IsTextureContentCached ambiguo/ausente: count=$($matches.Count)." }
    $m = $matches[0]
    $i = $m.Groups['indent'].Value
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @(
        "$i// $script:PresenterMarker",
        "$i// Resolve a sampler-only cache alias before AGC materializes/copies texels.",
        "$i// Exact cache validation (including sparse guest-content probing) remains authoritative.",
        "${i}private static readonly bool _preSnapshotSamplerAliasV74075 =",
        "$i    !string.Equals(",
        "$i        Environment.GetEnvironmentVariable(",
        ($i + '            "SHARPEMU_PRE_SNAPSHOT_SAMPLER_ALIAS"),'),
        ($i + '        "0",'),
        "$i        StringComparison.Ordinal);",
        "${i}private static long _v74075PreSnapshotSamplerAliasHitCount;",
        '',
        "${i}private static bool TextureIdentityMatchesExceptSamplerV74075(",
        "$i    in TextureContentIdentity candidate,",
        "$i    in TextureContentIdentity requested)",
        "$i{",
        "$i    return",
        "$i        candidate.Address == requested.Address &&",
        "$i        candidate.Width == requested.Width &&",
        "$i        candidate.Height == requested.Height &&",
        "$i        candidate.Format == requested.Format &&",
        "$i        candidate.NumberType == requested.NumberType &&",
        "$i        candidate.DstSelect == requested.DstSelect &&",
        "$i        candidate.TileMode == requested.TileMode &&",
        "$i        candidate.Pitch == requested.Pitch &&",
        "$i        candidate.Arrayed == requested.Arrayed &&",
        "$i        candidate.ArrayLayers == requested.ArrayLayers &&",
        "$i        candidate.Type == requested.Type &&",
        "$i        candidate.Depth == requested.Depth &&",
        "$i        candidate.MetadataAddress == requested.MetadataAddress &&",
        "$i        candidate.DescriptorFlags == requested.DescriptorFlags &&",
        "$i        candidate.BcSwizzle == requested.BcSwizzle &&",
        "$i        candidate.HasExtendedDescriptor == requested.HasExtendedDescriptor;",
        "$i}",
        '',
        "${i}internal static bool IsTextureContentCached(in TextureContentIdentity identity)",
        "$i{",
        "$i    if (IsExactTextureContentCachedV74075(identity))",
        "$i    {",
        "$i        return true;",
        "$i    }",
        '',
        "$i    if (!_preSnapshotSamplerAliasV74075 ||",
        "$i        identity.Address == 0 ||",
        "$i        _cachedTextureIdentities.IsEmpty)",
        "$i    {",
        "$i        return false;",
        "$i    }",
        '',
        "$i    foreach (var candidate in _cachedTextureIdentities.Keys)",
        "$i    {",
        "$i        if (candidate.Sampler.Equals(identity.Sampler) ||",
        "$i            !TextureIdentityMatchesExceptSamplerV74075(candidate, identity) ||",
        "$i            !IsExactTextureContentCachedV74075(candidate))",
        "$i        {",
        "$i            continue;",
        "$i        }",
        '',
        "$i        var hit = Interlocked.Increment(ref _v74075PreSnapshotSamplerAliasHitCount);",
        "$i        if (hit <= 64 || (hit & (hit - 1)) == 0)",
        "$i        {",
        "$i            Console.Error.WriteLine(",
        ($i + '                $"[V74.0.75][PRE_SNAPSHOT_SAMPLER_ALIAS] " +'),
        ($i + '                $"count={hit} addr=0x{identity.Address:X16} " +'),
        ($i + '                $"size={identity.Width}x{identity.Height} " +'),
        ($i + '                $"fmt={identity.Format}/{identity.NumberType} " +'),
        ($i + '                $"tile={identity.TileMode} source_copy=skipped");'),
        "$i        }",
        "$i        return true;",
        "$i    }",
        '',
        "$i    return false;",
        "$i}",
        ''
    )
    $block = $lines -join $nl
    $renamed = "${i}private static bool IsExactTextureContentCachedV74075(in TextureContentIdentity identity)"
    $patched = $text.Substring(0, $m.Index) + $block + $nl + $renamed + $text.Substring($m.Index + $m.Length)
    Write-Utf8NoBom $TargetPath $patched
    return $true
}

function Apply-AgcFlowPatch([string]$TargetPath) {
    $text = Get-Text $TargetPath
    if ($text.Contains($script:AgcMarker) -and
        $text.Contains('_v74075ProducerWakeDrainCount') -and
        $text.Contains($script:AllocMarker)) {
        return $false
    }
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

    # 1) Full-overwrite texture snapshots: skip CLR zero-fill before guest-memory read.
    $allocPattern = 'new\s+byte\s*\[\s*\(int\)physicalSourceByteCount\s*\]'
    $allocMatches = [regex]::Matches($text, $allocPattern)
    if ($allocMatches.Count -gt 0) {
        $text = [regex]::Replace(
            $text,
            $allocPattern,
            'GC.AllocateUninitializedArray<byte>((int)physicalSourceByteCount)')
    }
    if (-not $text.Contains($script:AllocMarker)) {
        $methodPattern = '(?m)^(?<indent>[ \t]*)private\s+static\s+bool\s+TryCreateGuestDrawTexture\s*\('
        $mm = [regex]::Matches($text, $methodPattern)
        if ($mm.Count -ne 1) { throw "$script:Tag AGC anchor TryCreateGuestDrawTexture count=$($mm.Count), esperado=1." }
        $mi = $mm[0]
        $indent = $mi.Groups['indent'].Value
        $comment = $indent + '// ' + $script:AllocMarker + $nl +
                   $indent + '// physicalSourceByteCount buffers are fully overwritten by TryReadTextureGuestMemory.' + $nl
        $text = $text.Substring(0, $mi.Index) + $comment + $text.Substring($mi.Index)
    }

    # 2) Keep a drain-capable CpuContext as soon as a waiter monitor is created.
    if (-not $text.Contains('V74.0.75 waiter drain context')) {
        $ctxPattern = '(?s)(var\s+monitorContext\s*=\s*new\s+CpuContext\(\s*submitContext\.Memory,\s*submitContext\.TargetGeneration\);)'
        $cm = [regex]::Matches($text, $ctxPattern)
        if ($cm.Count -ne 1) { throw "$script:Tag AGC monitorContext anchor count=$($cm.Count), esperado=1." }
        $replacement = $cm[0].Value + $nl +
            '        // V74.0.75 waiter drain context: GPU writeback/visibility callbacks can wake' + $nl +
            '        // the dedicated drain immediately instead of waiting for a later monitor poll.' + $nl +
            '        Volatile.Write(ref gpuState.PendingDrainContext, monitorContext);'
        $text = $text.Substring(0, $cm[0].Index) + $replacement + $text.Substring($cm[0].Index + $cm[0].Length)
    }

    # 3) Clear the retained context once there are no suspended DCBs.
    if (-not $text.Contains('V74.0.75 clear inactive waiter drain context')) {
        $emptyPattern = '(?s)if\s*\(remaining\s*==\s*0\)\s*\{\s*gpuState\.WaitMonitorRunning\s*=\s*false;\s*return;\s*\}'
        $em = [regex]::Matches($text, $emptyPattern)
        if ($em.Count -ne 1) { throw "$script:Tag AGC remaining==0 monitor anchor count=$($em.Count), esperado=1." }
        $replacement = 'if (remaining == 0)' + $nl +
            '                {' + $nl +
            '                    // V74.0.75 clear inactive waiter drain context.' + $nl +
            '                    Volatile.Write(ref gpuState.PendingDrainContext, null);' + $nl +
            '                    gpuState.WaitMonitorRunning = false;' + $nl +
            '                    return;' + $nl +
            '                }'
        $text = $text.Substring(0, $em[0].Index) + $replacement + $text.Substring($em[0].Index + $em[0].Length)
    }

    # 4) Do not wake a separate worker when this thread already owns the AGC gate.
    if (-not $text.Contains('V74.0.75 gate-owner drain coalescing')) {
        $requestPattern = '(?s)(Volatile\.Write\(ref\s+gpuState\.PendingDrainContext,\s*ctx\);\s*Interlocked\.Exchange\(ref\s+gpuState\.DrainPending,\s*1\);)'
        $rm = [regex]::Matches($text, $requestPattern)
        if ($rm.Count -ne 1) { throw "$script:Tag AGC RequestResumableDcbDrain anchor count=$($rm.Count), esperado=1." }
        $replacement = $rm[0].Value + $nl + $nl +
            '        // V74.0.75 gate-owner drain coalescing: the parser checks DrainPending' + $nl +
            '        // between PM4 packets, so starting another thread here only makes it block on Gate.' + $nl +
            '        if (_agcGateOwnerWaitDrainV74072 && Monitor.IsEntered(gpuState.Gate))' + $nl +
            '        {' + $nl +
            '            return;' + $nl +
            '        }'
        $text = $text.Substring(0, $rm[0].Index) + $replacement + $text.Substring($rm[0].Index + $rm[0].Length)
    }

    # 5) SignalGpuWaitMonitor becomes a coalesced signal + drain request while waiters exist.
    if (-not $text.Contains($script:AgcMarker)) {
        $signalPattern = '(?ms)^(?<indent>[ \t]*)private\s+static\s+void\s+SignalGpuWaitMonitor\s*\(\s*object\s+memory\s*\)\s*\{\s*memory\s*=\s*CanonicalMemory\(memory\);\s*if\s*\(!_submittedGpuStates\.TryGetValue\(memory,\s*out\s+var\s+gpuState\)\)\s*\{\s*return;\s*\}\s*lock\s*\(gpuState\.WaitMonitorSignalGate\)\s*\{\s*gpuState\.WaitMonitorSignalVersion\+\+;\s*Monitor\.Pulse\(gpuState\.WaitMonitorSignalGate\);\s*\}\s*\}'
        $sm = [regex]::Matches($text, $signalPattern)
        if ($sm.Count -ne 1) { throw "$script:Tag AGC SignalGpuWaitMonitor structural anchor count=$($sm.Count), esperado=1." }
        $i = $sm[0].Groups['indent'].Value
        $lines = @(
            "$i// $script:AgcMarker",
            "${i}private static long _v74075ProducerWakeDrainCount;",
            '',
            "${i}private static void SignalGpuWaitMonitor(object memory)",
            "$i{",
            "$i    memory = CanonicalMemory(memory);",
            "$i    if (!_submittedGpuStates.TryGetValue(memory, out var gpuState))",
            "$i    {",
            "$i        return;",
            "$i    }",
            '',
            "$i    lock (gpuState.WaitMonitorSignalGate)",
            "$i    {",
            "$i        gpuState.WaitMonitorSignalVersion++;",
            "$i        Monitor.Pulse(gpuState.WaitMonitorSignalGate);",
            "$i    }",
            '',
            "$i    // A registered wait monitor owns a reusable CpuContext. Producer evidence is",
            "$i    // already real and latched; requesting the existing coalesced drain does not",
            "$i    // synthesize a fence/value or bypass WAIT_REG_MEM comparison semantics.",
            "$i    if (Volatile.Read(ref gpuState.PendingDrainContext) is { } drainContext)",
            "$i    {",
            "$i        RequestResumableDcbDrain(drainContext, gpuState);",
            "$i        var count = Interlocked.Increment(ref _v74075ProducerWakeDrainCount);",
            "$i        if (count <= 32 || (count & (count - 1)) == 0)",
            "$i        {",
            "$i            Console.Error.WriteLine(",
            ($i + '                $"[V74.0.75][PRODUCER_WAKE_DRAIN] count={count} " +'),
            ($i + '                $"pending={Volatile.Read(ref gpuState.DrainPending)}");'),
            "$i        }",
            "$i    }",
            "$i}"
        )
        $replacement = $lines -join $nl
        $text = $text.Substring(0, $sm[0].Index) + $replacement + $text.Substring($sm[0].Index + $sm[0].Length)
    }

    Write-Utf8NoBom $TargetPath $text
    return $true
}

function Assert-PatchedStructure([string]$RepoRoot) {
    $presenter = Join-Path $RepoRoot $script:PresenterRel
    $agc = Join-Path $RepoRoot $script:AgcRel
    $p = Get-Text $presenter
    $a = Get-Text $agc

    $presenterAliasOk =
        ($p.Contains($script:PresenterMarker) -and $p.Contains('IsExactTextureContentCachedV74075')) -or
        ($p.Contains('SHARPEMU_V74_0_56_33_2_PRE_SNAPSHOT_SAMPLER_ALIAS_STRUCTURAL') -and $p.Contains('IsExactTextureContentCachedV74056332'))
    if (-not $presenterAliasOk) { throw "$script:Tag Pos-verificacao presenter alias falhou." }

    foreach ($needle in @(
        $script:AgcMarker,
        '_v74075ProducerWakeDrainCount',
        'V74.0.75 waiter drain context',
        'V74.0.75 clear inactive waiter drain context',
        'V74.0.75 gate-owner drain coalescing',
        $script:AllocMarker,
        'GC.AllocateUninitializedArray<byte>((int)physicalSourceByteCount)')) {
        if (-not $a.Contains($needle)) { throw "$script:Tag Pos-verificacao AGC falhou: ausente '$needle'." }
    }

    $oldAlloc = [regex]::Matches($a, 'new\s+byte\s*\[\s*\(int\)physicalSourceByteCount\s*\]').Count
    if ($oldAlloc -ne 0) { throw "$script:Tag Pos-verificacao: ainda existem $oldAlloc snapshots physicalSourceByteCount zerados." }
}
