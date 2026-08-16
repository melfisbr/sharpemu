param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=$null
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $ag=[IO.Path]::Combine($candidate,'SharpEmu.Libs\Agc\AgcExports.cs')
    $vp=[IO.Path]::Combine($candidate,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    if([IO.File]::Exists($ag) -and [IO.File]::Exists($vp)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
if($ah -ne '2A68E4F9E3BBAACC50409D03EB146235546392A8F036C8628D5CF6B2560E4DE1') {
    throw "V73.0.22 AgcExports not installed: $ah"
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
$out=[IO.Path]::Combine($repo,"SharpEmu_V73_0_22_TARGETLESS_UI_PERF_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out) | Out-Null
$stdout=[IO.Path]::Combine($out,'demons_stdout.log')
$stderr=[IO.Path]::Combine($out,'demons_stderr.log')

[IO.File]::Copy($agc,[IO.Path]::Combine($out,'AgcExports_V73_0_22.cs'),$true)
[IO.File]::Copy($presenter,[IO.Path]::Combine($out,'VulkanVideoPresenter_CURRENT.cs'),$true)

$vars=@(
    'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_SHADER',
    'SHARPEMU_LOG_VK_COMPUTE_RESOURCES',
    'SHARPEMU_TRACE_RENDER_WORK',
    'SHARPEMU_TRACE_ORDERED_ACTION_LATENCY',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_SCANOUT_RECOVERY',
    'SHARPEMU_RENDER_CHECKPOINTS'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try {
    Remove-Item Env:SHARPEMU_REPLAY_TARGETLESS_COMPOSITES -ErrorAction SilentlyContinue
    $env:SHARPEMU_LOG_AGC_SHADER='0'
    $env:SHARPEMU_LOG_VK_SHADER='0'
    $env:SHARPEMU_LOG_VK_COMPUTE_RESOURCES='0'
    $env:SHARPEMU_TRACE_RENDER_WORK='0'
    $env:SHARPEMU_TRACE_ORDERED_ACTION_LATENCY='0'
    $env:SHARPEMU_TRACE_DCC_ALIAS='0'
    $env:SHARPEMU_TRACE_GUEST_IMAGES='0'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='0'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'
    $env:SHARPEMU_RENDER_CHECKPOINTS='1'

    Write-Host '[V73.0.22] LOW-TRACE run. Replay must come from the PPSA01341 source rule, not an environment override.' -ForegroundColor Cyan
    Write-Host '[V73.0.22] Close SharpEmu as soon as LANGUAGE SELECT or the next interactive UI becomes visible.' -ForegroundColor Cyan

    $sw=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $exe -ArgumentList @($Eboot) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $p.WaitForExit()
    $p.WaitForExit()
    $sw.Stop()
    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
    $wallSeconds=[Math]::Round($sw.Elapsed.TotalSeconds,3)
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

$replay=@(M $se '[V73.0.22][DS_COMPOSITE_REPLAY]')
$flip=@(M $se '[V16][CP4_FLIP]')
$present=@(M $se '[V16][CP5_PRESENT]')
$arrayBase=@(M $se '[V74.0.23.1][ARRAY_BASELINE]')
$arrayOwner=@(M $se '[V74.0.15][ARRAY_SINGLEFLIGHT] owner')
$wait=@(M $se 'agc.wait_suspended')
$resume=@(M $se 'wait_resumed')
$guest=@(M $se 'Vulkan VideoOut presented guest frame')
$unresolved=@(M $se 'unresolved:')
$lost=@(M $se 'deviceLost=True')
$gather=@(M $so 'ResourcePool::GatherResourceFileInfo')
$mainLoop=@(M $so 'Starting main loop')

foreach($pair in @(
    @('DS_COMPOSITE_REPLAY.txt',$replay),
    @('FLIPS.txt',$flip),
    @('PRESENTS.txt',$present),
    @('ARRAY_BASELINE.txt',$arrayBase),
    @('ARRAY_OWNER.txt',$arrayOwner),
    @('WAIT_SUSPENDED.txt',$wait),
    @('WAIT_RESUMED.txt',$resume),
    @('MAIN_LOOP.txt',$mainLoop)
)){
    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($out,$pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=73.0.22',
    'mode=permanent-title-scoped-composite-replay+low-trace-performance',
    "eboot_sha256=$eh",
    "agc_sha256=$ah",
    "presenter_sha256=$((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)",
    "exit_code=$exitCode",
    "wall_seconds=$wallSeconds",
    "stderr_lines=$($se.Count)",
    "stdout_lines=$($so.Count)",
    "ds_composite_replay_markers=$($replay.Count)",
    "flip_checkpoints=$($flip.Count)",
    "cp5_present_success=$(@($present | Where-Object {$_ -match 'result=Success'}).Count)",
    "array_baseline=$($arrayBase.Count)",
    "array_owner=$($arrayOwner.Count)",
    "wait_suspended=$($wait.Count)",
    "wait_resumed=$($resume.Count)",
    "guest_frames=$($guest.Count)",
    "gather_resource=$($gather.Count)",
    "main_loop=$($mainLoop.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)
[IO.File]::WriteAllLines([IO.Path]::Combine($out,'SUMMARY.txt'),$summary,[Text.UTF8Encoding]::new($false))

$zip=$out+'.zip'
Compress-Archive -Path ([IO.Path]::Combine($out,'*')) -DestinationPath $zip -Force
Write-Host "[V73.0.22] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
