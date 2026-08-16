param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath($RepoRoot)
if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw "EBOOT missing: $Eboot"}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){throw "EBOOT differs from audited PPSA01341: $eh"}

$exe=$null
foreach($candidate in @(
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw 'SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $repo ("SharpEmu_V73_0_19_1_UI_TEXTURE_MATERIALIZATION_RESULT_$stamp")
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_LOG_GPU_DETILE',
    'SHARPEMU_TRACE_IMAGE_OVERLAP',
    'SHARPEMU_RENDER_CHECKPOINTS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}
try{
    $env:SHARPEMU_TRACE_GUEST_IMAGES='1'
    $env:SHARPEMU_LOG_GPU_DETILE='1'
    $env:SHARPEMU_TRACE_IMAGE_OVERLAP='1'
    $env:SHARPEMU_RENDER_CHECKPOINTS='1'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    Write-Host '[V73.0.19.1] Run Demons Souls through both videos.' -ForegroundColor Cyan
    Write-Host '[V73.0.19.1] After video 2, wait for UI/menu progression. Do not enable SHARPEMU_NO_TEXTURE_SKIP.'

    $p=Start-Process -FilePath $exe -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $p.WaitForExit();$p.WaitForExit()
    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
}
finally{
    foreach($v in $vars){
        if($null -eq $old[$v]){Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue}
        else{[Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')}
    }
}

$so=@();$se=@()
if(Test-Path $stdout){$so=@([IO.File]::ReadAllLines($stdout))}
if(Test-Path $stderr){$se=@([IO.File]::ReadAllLines($stderr))}
function Match([string[]]$lines,[string]$needle){
    @($lines | Where-Object { $_.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
}

$stale=@(Match $se '[V73.0.19.1][TEXTURE_CACHE_STALE]')
$refresh=@(Match $se '[V73.0.19.1][TEXTURE_CACHE_REFRESH]')
$fallback=@(Match $se 'agc.texture_fallback')
$detile=@(Match $se '[GPU-DETILE]')
$rtSampled=@(Match $se 'agc.rt_sampled')
$overlap=@(Match $se '[V23][IMAGE]')
$drawReject=@(Match $se 'agc.draw_reject')
$workTimeout=@(Match $se '[V73.0.17][WORK_TIMEOUT]')
$wait=@(Match $se 'agc.wait_suspended')
$resume=@(Match $se 'wait_resumed')
$flip=@(Match $se '[V16][CP4_FLIP]')
$guest=@(Match $se 'Vulkan VideoOut presented guest frame')
$scan=@(Match $se 'agc.scanout_lineage')
$unresolved=@(Match $se 'unresolved:')
$lost=@(Match $se 'deviceLost=True')
$gather=@(Match $so 'ResourcePool::GatherResourceFileInfo')

foreach($pair in @(
    @('TEXTURE_CACHE_STALE.txt',$stale),
    @('TEXTURE_CACHE_REFRESH.txt',$refresh),
    @('TEXTURE_FALLBACK.txt',$fallback),
    @('GPU_DETILE.txt',$detile),
    @('RT_SAMPLED.txt',$rtSampled),
    @('IMAGE_OVERLAP.txt',$overlap),
    @('DRAW_REJECT.txt',$drawReject),
    @('WORK_TIMEOUT.txt',$workTimeout),
    @('WAIT_SUSPENDED.txt',$wait),
    @('WAIT_RESUMED.txt',$resume),
    @('FLIPS.txt',$flip),
    @('GUEST_FRAMES.txt',$guest)
)){
    [IO.File]::WriteAllLines(
        (Join-Path $out $pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false)
    )
}

$summary=@(
    'version=73.0.19.1',
    'eboot_sha256=22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E',
    "exit_code=$exitCode",
    "texture_cache_stale=$($stale.Count)",
    "texture_cache_refresh=$($refresh.Count)",
    "texture_fallback=$($fallback.Count)",
    "gpu_detile_lines=$($detile.Count)",
    "rt_sampled=$($rtSampled.Count)",
    "image_overlap=$($overlap.Count)",
    "draw_reject=$($drawReject.Count)",
    "v73017_work_timeout=$($workTimeout.Count)",
    "gather_resource=$($gather.Count)",
    "wait_suspended=$($wait.Count)",
    "wait_resumed=$($resume.Count)",
    "flip_checkpoints=$($flip.Count)",
    "guest_frames=$($guest.Count)",
    "scanout_lineage=$($scan.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)
[IO.File]::WriteAllLines((Join-Path $out 'SUMMARY.txt'),$summary,[Text.UTF8Encoding]::new($false))
$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V73.0.19.1] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
