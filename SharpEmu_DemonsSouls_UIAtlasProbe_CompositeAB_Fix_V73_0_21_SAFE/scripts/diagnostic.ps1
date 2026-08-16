param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "Unexpected EBOOT SHA256: $eh"
}

$presenter=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
if(-not(Test-Path -LiteralPath $presenter)){
    $presenter=Join-Path $repo 'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
}
$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
if($ph -ne '1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385'){
    throw "V73.0.21 presenter not installed: $ph"
}

$exe=$null
foreach($candidate in @(
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){
        $exe=$candidate
        break
    }
}
if($null -eq $exe){throw 'SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $repo ("SharpEmu_V73_0_21_UI_ATLAS_COMPOSITE_AB_RESULT_$stamp")
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){
    $old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')
}

try{
    # IMPORTANT: this A/B switch already exists in the captured source. It is
    # enabled only for this child process and is restored afterwards.
    $env:SHARPEMU_REPLAY_TARGETLESS_COMPOSITES='1'
    $env:SHARPEMU_LOG_AGC_SHADER='1'
    $env:SHARPEMU_TRACE_DCC_ALIAS='1'
    $env:SHARPEMU_TRACE_GUEST_IMAGES='present'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    Write-Host '[V73.0.21] A/B run: targetless-composite replay is TEMPORARILY enabled for this diagnostic process.' -ForegroundColor Cyan
    Write-Host '[V73.0.21] Observe the transition after movie 2. If UI/menu appears, leave it visible for several frames, then close SharpEmu.' -ForegroundColor Cyan

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
finally{
    foreach($v in $vars){
        if($null -eq $old[$v]){
            Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')
        }
    }
}

$so=@()
$se=@()
if(Test-Path -LiteralPath $stdout){$so=@([IO.File]::ReadAllLines($stdout))}
if(Test-Path -LiteralPath $stderr){$se=@([IO.File]::ReadAllLines($stderr))}

function M([string[]]$l,[string]$n){
    @($l | Where-Object {$_.IndexOf($n,[StringComparison]::OrdinalIgnoreCase) -ge 0})
}

$replayed=@(M $se 'agc.deferred_composite_replayed_after_direct_writer')
$composites=@(M $se 'agc.deferred_composite index=')
$suppressed=@(M $se 'agc.deferred_composite_suppressed')
$array=@(M $se '[ARRAY_SINGLEFLIGHT] owner')
$array320=@($array | Where-Object {$_ -match '335544320'})
$stale=@(M $se 'TEXTURE_CACHE_STALE')
$refresh=@(M $se 'TEXTURE_CACHE_REFRESH')
$dcc45=@($se | Where-Object {
    $_ -match '45D550000' -and
    ($_ -match 'texture_dcc_alias_miss|unresolved_dcc_cpu_snapshot_suppressed')
})
$present=@(M $se '[V16][CP5_PRESENT]')
$guest=@(M $se 'Vulkan VideoOut presented guest frame')
$scanout=@(M $se 'agc.scanout_lineage')
$unresolved=@(M $se 'unresolved:')
$lost=@(M $se 'deviceLost=True')
$gather=@(M $so 'ResourcePool::GatherResourceFileInfo')

foreach($pair in @(
    @('COMPOSITE_REPLAY.txt',$replayed),
    @('COMPOSITES.txt',$composites),
    @('COMPOSITE_SUPPRESSED.txt',$suppressed),
    @('ARRAY_SINGLEFLIGHT.txt',$array),
    @('ARRAY_320M.txt',$array320),
    @('TEXTURE_CACHE_STALE.txt',$stale),
    @('TEXTURE_CACHE_REFRESH.txt',$refresh),
    @('DCC_45D550000.txt',$dcc45),
    @('PRESENTS.txt',$present),
    @('SCANOUT.txt',$scanout)
)){
    [IO.File]::WriteAllLines(
        (Join-Path $out $pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=73.0.21',
    'mode=large-probe-fix+temporary-targetless-replay-ab',
    'presenter_sha256=1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385',
    'eboot_sha256=22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E',
    "exit_code=$exitCode",
    "deferred_composite_replayed=$($replayed.Count)",
    "deferred_composite_draws=$($composites.Count)",
    "deferred_composite_suppressed=$($suppressed.Count)",
    "array_singleflight_owner=$($array.Count)",
    "array_320m_owner=$($array320.Count)",
    "texture_cache_stale=$($stale.Count)",
    "texture_cache_refresh=$($refresh.Count)",
    "dcc_45d550000_problem_lines=$($dcc45.Count)",
    "cp5_present_success=$(@($present | Where-Object {$_ -match 'result=Success'}).Count)",
    "guest_frames=$($guest.Count)",
    "scanout_lineage=$($scanout.Count)",
    "gather_resource=$($gather.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)

[IO.File]::WriteAllLines(
    (Join-Path $out 'SUMMARY.txt'),
    $summary,
    [Text.UTF8Encoding]::new($false))

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force

Write-Host "[V73.0.21] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
