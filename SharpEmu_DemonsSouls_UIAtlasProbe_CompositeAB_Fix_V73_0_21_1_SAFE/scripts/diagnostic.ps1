param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. ([IO.Path]::Combine($PSScriptRoot,'common.ps1'))

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=Resolve-SourceBase $repo
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$src=[IO.File]::ReadAllText($presenter)
$slice=Get-ProbeMethodSlice $src
if($slice.Text -match 'byteCount\s*>\s*MaxTrackedGuestImageBytes'){
    throw 'V73.0.21.1 probe fix is not installed.'
}

$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){throw "Unexpected EBOOT SHA256: $eh"}

$exe=$null
foreach($candidate in @(
    [IO.Path]::Combine($repo,'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    [IO.Path]::Combine($repo,'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if([IO.File]::Exists($candidate)){$exe=$candidate;break}
}
if($null -eq $exe){throw 'SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=[IO.Path]::Combine($repo,"SharpEmu_V73_0_21_1_UI_ATLAS_COMPOSITE_AB_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out) | Out-Null
$stdout=[IO.Path]::Combine($out,'demons_stdout.log')
$stderr=[IO.Path]::Combine($out,'demons_stderr.log')

$vars=@(
    'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try {
    $env:SHARPEMU_REPLAY_TARGETLESS_COMPOSITES='1'
    $env:SHARPEMU_LOG_AGC_SHADER='1'
    $env:SHARPEMU_TRACE_DCC_ALIAS='1'
    $env:SHARPEMU_TRACE_GUEST_IMAGES='present'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    Write-Host '[V73.0.21.1] TEMPORARY A/B: targetless composite replay enabled only for this test process.' -ForegroundColor Cyan
    Write-Host '[V73.0.21.1] Observe the screen after movie 2; if UI/menu appears, leave several frames visible and then close SharpEmu.' -ForegroundColor Cyan

    $p=Start-Process -FilePath $exe -ArgumentList @($Eboot) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $p.WaitForExit();$p.WaitForExit()
    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
}
finally {
    foreach($v in $vars){
        if($null -eq $old[$v]){Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue}
        else {[Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')}
    }
}

$so=@();$se=@()
if([IO.File]::Exists($stdout)){$so=@([IO.File]::ReadAllLines($stdout))}
if([IO.File]::Exists($stderr)){$se=@([IO.File]::ReadAllLines($stderr))}
function M([string[]]$l,[string]$n){@($l | Where-Object {$_.IndexOf($n,[StringComparison]::OrdinalIgnoreCase) -ge 0})}

$replayed=@(M $se 'agc.deferred_composite_replayed_after_direct_writer')
$composites=@(M $se 'agc.deferred_composite index=')
$suppressed=@(M $se 'agc.deferred_composite_suppressed')
$array=@(M $se '[ARRAY_SINGLEFLIGHT] owner')
$array320=@($array | Where-Object {$_ -match '335544320'})
$stale=@(M $se 'TEXTURE_CACHE_STALE')
$refresh=@(M $se 'TEXTURE_CACHE_REFRESH')
$dcc45=@($se | Where-Object {$_ -match '45D550000' -and ($_ -match 'texture_dcc_alias_miss|unresolved_dcc_cpu_snapshot_suppressed|texture addr=')})
$guest=@(M $se 'Vulkan VideoOut presented guest frame')
$scanout=@(M $se 'agc.scanout_lineage')
$unresolved=@(M $se 'unresolved:')
$lost=@(M $se 'deviceLost=True')
$gather=@(M $so 'ResourcePool::GatherResourceFileInfo')
$wait=@(M $se 'agc.wait_suspended')

foreach($pair in @(
    @('COMPOSITE_REPLAY.txt',$replayed),
    @('COMPOSITES.txt',$composites),
    @('COMPOSITE_SUPPRESSED.txt',$suppressed),
    @('ARRAY_SINGLEFLIGHT.txt',$array),
    @('ARRAY_320M.txt',$array320),
    @('TEXTURE_CACHE_STALE.txt',$stale),
    @('TEXTURE_CACHE_REFRESH.txt',$refresh),
    @('DCC_45D550000.txt',$dcc45),
    @('SCANOUT.txt',$scanout),
    @('WAITS.txt',$wait)
)){
    [IO.File]::WriteAllLines([IO.Path]::Combine($out,$pair[0]),[string[]]$pair[1],[Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=73.0.21.1',
    'mode=bounded-large-probe-fix+temporary-targetless-replay-ab',
    "presenter_sha256=$((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)",
    "eboot_sha256=$eh",
    "exit_code=$exitCode",
    "deferred_composite_replayed=$($replayed.Count)",
    "deferred_composite_draws=$($composites.Count)",
    "deferred_composite_suppressed=$($suppressed.Count)",
    "array_singleflight_owner=$($array.Count)",
    "array_320m_owner=$($array320.Count)",
    "texture_cache_stale=$($stale.Count)",
    "texture_cache_refresh=$($refresh.Count)",
    "dcc_45d550000_problem_lines=$($dcc45.Count)",
    "guest_frames=$($guest.Count)",
    "scanout_lineage=$($scanout.Count)",
    "wait_suspended=$($wait.Count)",
    "gather_resource=$($gather.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)
[IO.File]::WriteAllLines([IO.Path]::Combine($out,'SUMMARY.txt'),$summary,[Text.UTF8Encoding]::new($false))
[IO.File]::Copy($presenter,[IO.Path]::Combine($out,'VulkanVideoPresenter_AFTER_V73_0_21_1.cs'),$true)
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
[IO.File]::Copy($agc,[IO.Path]::Combine($out,'AgcExports_CURRENT.cs'),$true)

$zip=$out+'.zip'
Compress-Archive -Path ([IO.Path]::Combine($out,'*')) -DestinationPath $zip -Force
Write-Host "[V73.0.21.1] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
