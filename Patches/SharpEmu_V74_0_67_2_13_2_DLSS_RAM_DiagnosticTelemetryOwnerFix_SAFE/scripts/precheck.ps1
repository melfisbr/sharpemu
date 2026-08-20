. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

foreach($path in @($bridge,$agc,$exceptions)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing source: $path"}
}

$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$a=Normalize-Lf ([IO.File]::ReadAllText($agc))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))

$checks=[ordered]@{
    v213_dlss_retry=
        $b.Contains('V74.0.67.2.13 bounded provider activation retry')
    v213_active_telemetry_owner=
        $b.Contains('[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active')
    provider_initialized_property=
        $b.Contains('public bool IsInitialized => _initialized;')
    retry_timer=
        $b.Contains('V74067213ProviderRetryMs = 2000')
    provider_retention=
        $b.Contains('provider_loaded=1')
    last_error=
        $b.Contains('public string LastError')
    v213_ram_identity=
        $a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    ram_content_key=
        $a.Contains('ulong ContentKey,')
    ram_sparse_probe=
        $a.Contains('ComputeV74067213LargeArrayContentKey(')
    ram_v74064_ttl=
        $a.Contains('_v74064LargeArraySnapshotTtlMs') -and
        $a.Contains('SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS')
    ram_v74064_multicache=
        $a.Contains('TryGetLargeArraySnapshotV74064') -and
        $a.Contains('StoreLargeArraySnapshotV74064')
    bpe_v212=
        $e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.13.2] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.13.2] diagnostic_fix=source-telemetry-owner-is-v2.13'
Write-Host '[V74.0.67.2.13.2] runtime_source_change=false'

if($failed){throw '[V74.0.67.2.13.2] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.13.2] PRECHECK PASSED.'
