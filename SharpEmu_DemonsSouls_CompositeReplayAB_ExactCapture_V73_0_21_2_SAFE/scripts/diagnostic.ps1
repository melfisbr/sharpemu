param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. ([IO.Path]::Combine($PSScriptRoot,'common.ps1'))

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=Resolve-SourceBase $repo
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
Require-ReplaySwitch $agc

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
$out=[IO.Path]::Combine($repo,"SharpEmu_V73_0_21_2_COMPOSITE_AB_EXACT_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out) | Out-Null

# Capture exact source BEFORE runtime.
[IO.File]::Copy($presenter,[IO.Path]::Combine($out,'VulkanVideoPresenter_BEFORE.cs'),$true)
[IO.File]::Copy($agc,[IO.Path]::Combine($out,'AgcExports_BEFORE.cs'),$true)
$phBefore=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ahBefore=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

$stdout=[IO.Path]::Combine($out,'demons_stdout.log')
$stderr=[IO.Path]::Combine($out,'demons_stderr.log')

$vars=@(
    'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_RENDER_CHECKPOINTS',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){
    $old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')
}

try {
    $env:SHARPEMU_REPLAY_TARGETLESS_COMPOSITES='1'
    $env:SHARPEMU_LOG_AGC_SHADER='1'
    $env:SHARPEMU_TRACE_DCC_ALIAS='1'
    $env:SHARPEMU_TRACE_GUEST_IMAGES='present'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_RENDER_CHECKPOINTS='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    Write-Host '[V73.0.21.2] A/B TEST: targetless-composite replay enabled ONLY for this SharpEmu process.' -ForegroundColor Cyan
    Write-Host '[V73.0.21.2] Observe after movie 2. If anything appears (menu/UI/scene/artifacts), leave several frames visible, then close SharpEmu.' -ForegroundColor Cyan

    $p=Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $p.WaitForExit()
    $p.WaitForExit()
    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
}
finally {
    foreach($v in $vars){
        if($null -eq $old[$v]){
            Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $v,[string]$old[$v],'Process')
        }
    }
}

$phAfter=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ahAfter=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
if($phAfter -ne $phBefore -or $ahAfter -ne $ahBefore){
    throw 'RUNTIME READ-ONLY INVARIANT FAILED: source hash changed during diagnostic.'
}

# Capture exact source AFTER runtime too (should be byte-identical).
[IO.File]::Copy($presenter,[IO.Path]::Combine($out,'VulkanVideoPresenter_AFTER.cs'),$true)
[IO.File]::Copy($agc,[IO.Path]::Combine($out,'AgcExports_AFTER.cs'),$true)

$so=@()
$se=@()
if([IO.File]::Exists($stdout)){$so=@([IO.File]::ReadAllLines($stdout))}
if([IO.File]::Exists($stderr)){$se=@([IO.File]::ReadAllLines($stderr))}

function M([string[]]$lines,[string]$needle){
    @($lines | Where-Object {
        $_.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0
    })
}

$replayed=@(M $se 'deferred_composite_replayed_after_direct_writer')
$composites=@(M $se 'deferred_composite index=')
$suppressed=@(M $se 'deferred_composite_suppressed')
$targetless=@(M $se 'PendingTargetless')
$array=@(M $se '[ARRAY_SINGLEFLIGHT] owner')
$array320=@($array | Where-Object {$_ -match '335544320|320 MiB|320MiB'})
$stale=@(M $se 'TEXTURE_CACHE_STALE')
$refresh=@(M $se 'TEXTURE_CACHE_REFRESH')
$dcc45=@($se | Where-Object {
    $_ -match '45D550000' -and
    ($_ -match 'texture_dcc_alias_miss|unresolved_dcc_cpu_snapshot_suppressed|texture_source|texture_gpu_writer')
})
$rtSampled=@(M $se 'agc.rt_sampled')
$flip=@(M $se '[V16][CP4_FLIP]')
$present=@(M $se '[V16][CP5_PRESENT]')
$guest=@(M $se 'Vulkan VideoOut presented guest frame')
$scanout=@(M $se 'scanout_lineage')
$wait=@(M $se 'wait_suspended')
$resume=@(M $se 'wait_resumed')
$unresolved=@(M $se 'unresolved:')
$lost=@(M $se 'deviceLost=True')
$gather=@(M $so 'ResourcePool::GatherResourceFileInfo')

foreach($pair in @(
    @('COMPOSITE_REPLAY.txt',$replayed),
    @('COMPOSITES.txt',$composites),
    @('COMPOSITE_SUPPRESSED.txt',$suppressed),
    @('TARGETLESS.txt',$targetless),
    @('ARRAY_SINGLEFLIGHT.txt',$array),
    @('ARRAY_320M.txt',$array320),
    @('TEXTURE_CACHE_STALE.txt',$stale),
    @('TEXTURE_CACHE_REFRESH.txt',$refresh),
    @('DCC_45D550000.txt',$dcc45),
    @('RT_SAMPLED.txt',$rtSampled),
    @('FLIPS.txt',$flip),
    @('PRESENTS.txt',$present),
    @('SCANOUT.txt',$scanout),
    @('WAIT_SUSPENDED.txt',$wait),
    @('WAIT_RESUMED.txt',$resume)
)){
    Write-Utf8NoBom ([IO.Path]::Combine($out,$pair[0])) ([string[]]$pair[1])
}

$summary=@(
    'version=73.0.21.2',
    'mode=read-only-build+temporary-targetless-composite-replay-ab',
    "eboot_sha256=$eh",
    "presenter_sha256=$phAfter",
    "agc_sha256=$ahAfter",
    "exit_code=$exitCode",
    "deferred_composite_replayed=$($replayed.Count)",
    "deferred_composite_draws=$($composites.Count)",
    "deferred_composite_suppressed=$($suppressed.Count)",
    "targetless_trace_lines=$($targetless.Count)",
    "array_singleflight_owner=$($array.Count)",
    "array_320m_owner=$($array320.Count)",
    "texture_cache_stale=$($stale.Count)",
    "texture_cache_refresh=$($refresh.Count)",
    "dcc_45d550000_problem_lines=$($dcc45.Count)",
    "rt_sampled=$($rtSampled.Count)",
    "flip_checkpoints=$($flip.Count)",
    "cp5_present_success=$(@($present | Where-Object {$_ -match 'result=Success'}).Count)",
    "guest_frames=$($guest.Count)",
    "scanout_lineage=$($scanout.Count)",
    "wait_suspended=$($wait.Count)",
    "wait_resumed=$($resume.Count)",
    "gather_resource=$($gather.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)
Write-Utf8NoBom ([IO.Path]::Combine($out,'SUMMARY.txt')) $summary

# Provenance / current git diff, non-fatal.
try {
    $head=& git -C $repo rev-parse HEAD 2>&1
    Write-Utf8NoBom ([IO.Path]::Combine($out,'GIT_HEAD.txt')) ([string[]]@($head))
    $status=& git -C $repo status --short 2>&1
    Write-Utf8NoBom ([IO.Path]::Combine($out,'GIT_STATUS.txt')) ([string[]]@($status))
    $diff=& git -C $repo --no-pager diff -- `
        'src/SharpEmu.Libs/Agc/AgcExports.cs' `
        'src/SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs' 2>&1
    Write-Utf8NoBom ([IO.Path]::Combine($out,'CURRENT_SOURCE_DIFF.txt')) ([string[]]@($diff))
} catch {
    Write-Utf8NoBom ([IO.Path]::Combine($out,'GIT_CAPTURE_ERROR.txt')) ([string[]]@($_.Exception.Message))
}

$zip=$out+'.zip'
Compress-Archive -Path ([IO.Path]::Combine($out,'*')) -DestinationPath $zip -Force

Write-Host '[V73.0.21.2] READ-ONLY A/B completed; source hashes unchanged.' -ForegroundColor Green
Write-Host "[V73.0.21.2] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
