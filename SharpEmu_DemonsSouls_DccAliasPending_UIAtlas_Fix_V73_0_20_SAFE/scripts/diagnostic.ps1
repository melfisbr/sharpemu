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
$out=Join-Path $repo (
    "SharpEmu_V73_0_20_DCC_ALIAS_UI_RESULT_$stamp")
New-Item -ItemType Directory -Force -Path $out | Out-Null

$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_RENDER_CHECKPOINTS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){
    $old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')
}

try{
    $env:SHARPEMU_TRACE_DCC_ALIAS='1'
    $env:SHARPEMU_TRACE_GUEST_IMAGES='present'
    $env:SHARPEMU_RENDER_CHECKPOINTS='1'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    Write-Host '[V73.0.20] Run Demon''s Souls through movie 2 and keep it on the black/menu transition long enough for several flips.' -ForegroundColor Cyan

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
            [Environment]::SetEnvironmentVariable(
                $v,
                [string]$old[$v],
                'Process')
        }
    }
}

$so=@()
$se=@()
if(Test-Path -LiteralPath $stdout){
    $so=@([IO.File]::ReadAllLines($stdout))
}
if(Test-Path -LiteralPath $stderr){
    $se=@([IO.File]::ReadAllLines($stderr))
}

function Match([string[]]$lines,[string]$needle){
    @($lines | Where-Object {
        $_.IndexOf(
            $needle,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
}

$pending=@(Match $se '[V73.0.20][DCC_ALIAS_PENDING]')
$seeded=@(Match $se '[V73.0.20][LARGE_PROBE_SEEDED]')
$aliasHit=@(Match $se 'agc.texture_dcc_alias_hit')
$aliasMiss=@(Match $se 'agc.texture_dcc_alias_miss')
$dccSuppressed=@(Match $se 'unresolved_dcc_cpu_snapshot_suppressed')
$largeSnapshot=@(Match $se 'large_texture_cpu_snapshot')
$stale=@(Match $se 'TEXTURE_CACHE_STALE')
$refresh=@(Match $se 'TEXTURE_CACHE_REFRESH')
$arrayOwner=@(Match $se '[ARRAY_SINGLEFLIGHT] owner')
$rtSampled=@(Match $se 'agc.rt_sampled')
$guestImage=@(Match $se 'vk.guest_image')
$flip=@(Match $se '[V16][CP4_FLIP]')
$present=@(Match $se '[V16][CP5_PRESENT]')
$bindings=@(Match $se '[V16][CP3_BINDINGS]')
$wait=@(Match $se 'agc.wait_suspended')
$resume=@(Match $se 'wait_resumed')
$unresolved=@(Match $se 'unresolved:')
$lost=@(Match $se 'deviceLost=True')
$gather=@(Match $so 'ResourcePool::GatherResourceFileInfo')

foreach($pair in @(
    @('DCC_ALIAS_PENDING.txt',$pending),
    @('DCC_ALIAS_HIT.txt',$aliasHit),
    @('DCC_ALIAS_MISS.txt',$aliasMiss),
    @('DCC_CPU_SNAPSHOT_SUPPRESSED.txt',$dccSuppressed),
    @('LARGE_PROBE_SEEDED.txt',$seeded),
    @('TEXTURE_CACHE_STALE.txt',$stale),
    @('TEXTURE_CACHE_REFRESH.txt',$refresh),
    @('ARRAY_OWNER.txt',$arrayOwner),
    @('RT_SAMPLED.txt',$rtSampled),
    @('GUEST_IMAGE.txt',$guestImage),
    @('FLIPS.txt',$flip),
    @('PRESENTS.txt',$present),
    @('BINDINGS.txt',$bindings),
    @('WAIT_SUSPENDED.txt',$wait),
    @('WAIT_RESUMED.txt',$resume)
)){
    [IO.File]::WriteAllLines(
        (Join-Path $out $pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=73.0.20',
    'eboot_sha256=22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E',
    "exit_code=$exitCode",
    "dcc_alias_pending=$($pending.Count)",
    "dcc_alias_hit=$($aliasHit.Count)",
    "dcc_alias_miss=$($aliasMiss.Count)",
    "dcc_cpu_snapshot_suppressed=$($dccSuppressed.Count)",
    "large_probe_seeded=$($seeded.Count)",
    "large_texture_snapshot=$($largeSnapshot.Count)",
    "texture_cache_stale=$($stale.Count)",
    "texture_cache_refresh=$($refresh.Count)",
    "array_singleflight_owner=$($arrayOwner.Count)",
    "rt_sampled=$($rtSampled.Count)",
    "flip_checkpoints=$($flip.Count)",
    "cp5_present_success=$(@($present | Where-Object {$_ -match 'result=Success'}).Count)",
    "wait_suspended=$($wait.Count)",
    "wait_resumed=$($resume.Count)",
    "gather_resource=$($gather.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)

[IO.File]::WriteAllLines(
    (Join-Path $out 'SUMMARY.txt'),
    $summary,
    [Text.UTF8Encoding]::new($false))

$zip=$out+'.zip'
Compress-Archive `
    -Path (Join-Path $out '*') `
    -DestinationPath $zip `
    -Force

Write-Host "[V73.0.20] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
