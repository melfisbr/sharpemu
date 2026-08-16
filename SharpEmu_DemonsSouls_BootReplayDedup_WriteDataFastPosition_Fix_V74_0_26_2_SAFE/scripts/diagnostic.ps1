param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Resolve-RepoV740262 -RepositoryRoot $RepositoryRoot
$agcPath=Get-AgcV740262 -Root $root
$hostMoviePath=Get-HostMovieV740262 -Root $root

$ah=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
if($ah -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){
    throw "[V74.0.26.2] AGC correction not installed: $ah"
}
$mediaText=[IO.File]::ReadAllText($hostMoviePath)
if(-not(Test-MediaReplayDedupeV740262 -Text $mediaText)){
    throw '[V74.0.26.2] Existing V31.7.9 dedupe capability disappeared.'
}

$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "[V74.0.26.2] EBOOT SHA256 mismatch: $eh"
}

$releaseRoot=[IO.Path]::Combine(
    $root,'artifacts','bin','Release','net10.0','win-x64')
$exe=[IO.Path]::Combine($releaseRoot,'SharpEmu.exe')
$dll=[IO.Path]::Combine($releaseRoot,'SharpEmu.dll')

if([IO.File]::Exists($exe)){
    $launchFile=$exe
    $launchArgs=@($Eboot)
} elseif([IO.File]::Exists($dll)){
    $launchFile='dotnet'
    $launchArgs=@($dll,$Eboot)
} else {
    throw '[V74.0.26.2] Release executable/DLL not found.'
}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=[IO.Path]::Combine(
    $root,
    "SharpEmu_V74_0_26_2_FAST_WRITE_DEDUPE_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out)|Out-Null

$stdout=[IO.Path]::Combine($out,'stdout.log')
$stderr=[IO.Path]::Combine($out,'stderr.log')

# Exact sources used by this test.
[IO.File]::Copy(
    $agcPath,
    [IO.Path]::Combine($out,'AgcExports_V74_0_26_2.cs'),
    $true)
[IO.File]::Copy(
    $hostMoviePath,
    [IO.Path]::Combine($out,'HostMovieBridge_CURRENT.cs'),
    $true)

$vars=@(
    'SHARPEMU_WRITE_DATA_PACKET_POSITION',
    'SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_SHADER',
    'SHARPEMU_LOG_VK_COMPUTE_RESOURCES',
    'SHARPEMU_TRACE_RENDER_WORK',
    'SHARPEMU_TRACE_ORDERED_ACTION_LATENCY',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_TRACE_GUEST_IMAGES',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_PROFILE_RENDER',
    'SHARPEMU_PERF_MEM',
    'SHARPEMU_OVERLAY'
)
$old=@{}
foreach($name in $vars){
    $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}

try{
    $env:SHARPEMU_WRITE_DATA_PACKET_POSITION='1'
    # Use the V31.7.9 capability exactly as its own diagnostic did. No source
    # rewrite is required to prove or use the dedupe.
    $env:SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY='1'

    foreach($name in @(
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_SHADER',
        'SHARPEMU_LOG_VK_COMPUTE_RESOURCES',
        'SHARPEMU_TRACE_RENDER_WORK',
        'SHARPEMU_TRACE_ORDERED_ACTION_LATENCY',
        'SHARPEMU_TRACE_DCC_ALIAS',
        'SHARPEMU_TRACE_GUEST_IMAGES',
        'SHARPEMU_TRACE_SCANOUT_LINEAGE',
        'SHARPEMU_PROFILE_RENDER',
        'SHARPEMU_PERF_MEM',
        'SHARPEMU_OVERLAY'
    )){
        [Environment]::SetEnvironmentVariable($name,'0','Process')
    }

    Write-Host '[V74.0.26.2] RELEASE low-trace test.' -ForegroundColor Cyan
    Write-Host '[V74.0.26.2] Existing V31.7.9 guest-replay dedupe is explicitly ENABLED by environment; HostMovieBridge source is untouched.' -ForegroundColor Cyan
    Write-Host '[V74.0.26.2] Expected: host direct boot may show PS Studios once; first natural guest reopen should log bink2.guest_replay_deduped and NOT launch a second RAD.' -ForegroundColor Cyan
    Write-Host '[V74.0.26.2] Close SharpEmu when LANGUAGE SELECT/interactive UI appears.' -ForegroundColor Cyan

    $sw=[Diagnostics.Stopwatch]::StartNew()
    $processObject=Start-Process `
        -FilePath $launchFile `
        -ArgumentList $launchArgs `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $processObject.WaitForExit()
    $processObject.WaitForExit()
    $sw.Stop()

    try{$exitCode=$processObject.ExitCode}catch{$exitCode='unavailable'}
    $wallSeconds=[Math]::Round($sw.Elapsed.TotalSeconds,3)
}
finally{
    foreach($name in $vars){
        if($null -eq $old[$name]){
            Remove-Item ('Env:'+$name) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $name,[string]$old[$name],'Process')
        }
    }
}

$so=@()
$se=@()
if([IO.File]::Exists($stdout)){$so=@([IO.File]::ReadAllLines($stdout))}
if([IO.File]::Exists($stderr)){$se=@([IO.File]::ReadAllLines($stderr))}

function Find-LinesV740262([string[]]$Lines,[string]$Needle){
    return @($Lines|Where-Object{
        $_.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase)-ge 0
    })
}

$directDone=-1
for($i=0;$i -lt $se.Count;$i++){
    if($directDone -lt 0 -and $se[$i] -match 'bink2\.direct_boot_completed'){
        $directDone=$i
    }
}

$psAll=@($se|Where-Object{
    $_ -match 'Bink RAD bridge attached: ps_studios_logo\.bk2'
})
$psAfterDirect=@()
if($directDone -ge 0){
    for($i=$directDone+1;$i -lt $se.Count;$i++){
        if($se[$i] -match 'Bink RAD bridge attached: ps_studios_logo\.bk2'){
            $psAfterDirect += $se[$i]
        }
    }
}

$natural=@(Find-LinesV740262 $se 'bink2.natural_guest_movie_observed')
$deduped=@(Find-LinesV740262 $se 'bink2.guest_replay_deduped')
$reconcileDone=@(Find-LinesV740262 $se 'bink2.guest_boot_reconciliation_completed')
$waitLines=@(Find-LinesV740262 $se '[V74.0.25][WAIT_RESUME]')
$writePosition=@(Find-LinesV740262 $se '[V74.0.25][WRITE_DATA_PACKET_POSITION]')
$guestFrames=@(Find-LinesV740262 $se 'Vulkan VideoOut presented guest frame')
$mainLoop=@(Find-LinesV740262 $so 'Starting main loop')
$unresolved=@(Find-LinesV740262 $se 'unresolved:')
$deviceLost=@(Find-LinesV740262 $se 'deviceLost=True')

$waitValues=New-Object 'Collections.Generic.List[double]'
foreach($line in $waitLines){
    if($line -match 'waited_ms=([0-9]+[\.,][0-9]+)'){
        $value=[double]::Parse(
            $matches[1].Replace(',','.'),
            [Globalization.CultureInfo]::InvariantCulture)
        $waitValues.Add($value)
    }
}
$maxWait=if($waitValues.Count -gt 0){($waitValues|Measure-Object -Maximum).Maximum}else{0.0}
$avgWait=if($waitValues.Count -gt 0){($waitValues|Measure-Object -Average).Average}else{0.0}
$over1s=@($waitValues|Where-Object{$_ -ge 1000.0}).Count
$over4s=@($waitValues|Where-Object{$_ -ge 4000.0}).Count

foreach($pair in @(
    @('PS_STUDIOS_ATTACH_ALL.txt',$psAll),
    @('PS_STUDIOS_ATTACH_POST_DIRECT.txt',$psAfterDirect),
    @('NATURAL_GUEST_MOVIES.txt',$natural),
    @('GUEST_REPLAY_DEDUPED.txt',$deduped),
    @('RECONCILIATION_COMPLETED.txt',$reconcileDone),
    @('WAIT_RESUME.txt',$waitLines),
    @('WRITE_DATA_PACKET_POSITION.txt',$writePosition)
)){
    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($out,$pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=74.0.26.2',
    'mode=exact-agc-no-readback+existing-v3179-dedupe-env',
    "wall_seconds=$wallSeconds",
    "exit_code=$exitCode",
    "stderr_lines=$($se.Count)",
    "stdout_lines=$($so.Count)",
    "agc_sha256=$ah",
    "host_movie_sha256=$((Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash)",
    'host_movie_source_modified=False',
    'bink_dedupe_env=1',
    "ps_studios_rad_attaches_total=$($psAll.Count)",
    "ps_studios_rad_attaches_post_direct=$($psAfterDirect.Count)",
    "natural_guest_movie_observed=$($natural.Count)",
    "guest_replay_deduped=$($deduped.Count)",
    "guest_boot_reconciliation_completed=$($reconcileDone.Count)",
    "write_data_packet_position_logs=$($writePosition.Count)",
    "wait_resume_logs=$($waitLines.Count)",
    "wait_max_ms=$([Math]::Round([double]$maxWait,3))",
    "wait_avg_ms=$([Math]::Round([double]$avgWait,3))",
    "wait_over_1s=$over1s",
    "wait_over_4s=$over4s",
    "guest_frames=$($guestFrames.Count)",
    "main_loop=$($mainLoop.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($deviceLost.Count)"
)

[IO.File]::WriteAllLines(
    [IO.Path]::Combine($out,'SUMMARY.txt'),
    $summary,
    [Text.UTF8Encoding]::new($false))

$zip=$out+'.zip'
Compress-Archive `
    -Path ([IO.Path]::Combine($out,'*')) `
    -DestinationPath $zip `
    -Force

Write-Host "[V74.0.26.2] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
