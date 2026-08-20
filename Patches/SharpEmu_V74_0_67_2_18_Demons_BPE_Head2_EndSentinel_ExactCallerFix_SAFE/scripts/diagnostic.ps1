. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'

$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$a=Normalize-Lf ([IO.File]::ReadAllText($agc))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))

$start=$e.IndexOf(
    'private unsafe static bool TryRecoverDemonBpeHead2EndSentinelFaultV74067218(',
    [StringComparison]::Ordinal)
$end=if($start-ge 0){
    $e.IndexOf(
        '	// V74.0.67.2.4.1 BPE low-sentinel linked-list recovery.',
        $start,
        [StringComparison]::Ordinal)
}else{-1}
$method=if($start-ge 0 -and $end-gt $start){
    $e.Substring($start,$end-$start)
}else{''}

$checks=[ordered]@{
    head2_marker=$e.Contains('V74.0.67.2.18 BPE head2 end-sentinel recovery')
    head2_handler=$e.Contains('TryRecoverDemonBpeHead2EndSentinelFaultV74067218(')
    exact_target=$method.Contains('er->ExceptionInformation[1] != 0xA')
    exact_rcx2=$method.Contains('rcx != 2')
    exact_rax2=$method.Contains('rax != 2')
    exact_primary_r14=$method.Contains('rdi != r14')
    exact_head2=$method.Contains('head != 2')
    exact_adjacent0=$method.Contains('adjacent != 0')
    helper_signature=$method.Contains('0x48, 0x8B, 0x49, 0x08')
    caller_mov_r14_cmp=$method.Contains('0xF390853B48C68949UL')
    caller_cmp_je=$method.Contains('0x840FFFFFUL')
    caller_deref_r14_20=$method.Contains('0x20468B41UL')
    caller_end_slot=$method.Contains('callerEndSlot = rbp - 0xC70')
    caller_end_matches_payload=$method.Contains('callerEndSentinel != payload')
    returns_payload=$method.Contains('WriteCtxU64(ctx, CTX_RAX, payload);')
    clears_rcx=$method.Contains('WriteCtxU64(ctx, CTX_RCX, 0);')
    resumes_guest=$method.Contains('WriteCtxU64(ctx, CTX_RIP, rip + 4);')
    telemetry=$method.Contains('[V74.0.67.2.18][BPE_HEAD2_SENTINEL_RECOVERY]')
    v211_preserved=$e.Contains('V74.0.67.2.11 BPE end-sentinel return repair')
    v212_preserved=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    v217_cache=$a.Contains('V74.0.67.2.17 size-aware large-array admission')
    v217_small_write=$a.Contains('V74.0.67.2.17 small WRITE_DATA packet position')
    v217_latency=$a.Contains('V74.0.67.2.17 producer completion latency')
    v215_ttl=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    v214_dlss=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.18] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

$releaseHost=Find-ReleaseHost -Repo $repo
$hostOk=$null-ne $releaseHost
$line="[V74.0.67.2.18] release_host_exists=$($hostOk.ToString().ToLowerInvariant())"
Write-Host $line
$result.Add($line)
if(!$hostOk){$failed=$true}

$result.Add('[V74.0.67.2.18] RECOVERY_SCOPE=target0xA+rcx2+rax2+BPE+tcVi5SivF7Q+rdi-r14+helper-signature+head2+adjacent0+exact-caller+caller-end-payload')
$result.Add('[V74.0.67.2.18] RECOVERY_ACTION=RAX=canonical-payload RCX=0 RIP=rip+4')
$result.Add('[V74.0.67.2.18] ABSOLUTE_GUEST_ADDRESS_GATE=false')
$result.Add('[V74.0.67.2.18] DLSS_CHANGE=false')
$result.Add('[V74.0.67.2.18] V217_CHANGE=preserved-or-cumulative-apply-only')

if($failed){throw '[V74.0.67.2.18] STRUCTURAL DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.18] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.18] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_18_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_18_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.18] ResultZip=$zip"
