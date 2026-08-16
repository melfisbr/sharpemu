param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Resolve-RepoV740263 -RepositoryRoot $RepositoryRoot
$agcPath=Get-AgcPathV740263 -Root $root
$hostMoviePath=Get-HostMoviePathV740263 -Root $root

$agcHash=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
if($agcHash -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){
    throw "[V74.0.26.3] AGC correction not installed: $agcHash"
}

$ebootHash=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($ebootHash -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "[V74.0.26.3] EBOOT SHA256 mismatch: $ebootHash"
}

$releaseRoot=[IO.Path]::Combine(
    $root,'artifacts','bin','Release','net10.0','win-x64')
$exe=[IO.Path]::Combine($releaseRoot,'SharpEmu.exe')
$dll=[IO.Path]::Combine($releaseRoot,'SharpEmu.dll')

if([IO.File]::Exists($exe)){
    $launchFile=$exe
    $launchArguments=@($Eboot)
} elseif([IO.File]::Exists($dll)){
    $launchFile='dotnet'
    $launchArguments=@($dll,$Eboot)
} else {
    throw '[V74.0.26.3] Release executable/DLL not found.'
}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=[IO.Path]::Combine(
    $root,
    "SharpEmu_V74_0_26_3_GUEST_OWNED_FAST_WRITE_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out)|Out-Null

$stdout=[IO.Path]::Combine($out,'stdout.log')
$stderr=[IO.Path]::Combine($out,'stderr.log')

[IO.File]::Copy(
    $agcPath,
    [IO.Path]::Combine($out,'AgcExports_V74_0_26_3.cs'),
    $true)
[IO.File]::Copy(
    $hostMoviePath,
    [IO.Path]::Combine($out,'HostMovieBridge_CURRENT.cs'),
    $true)

$environmentNames=@(
    'SHARPEMU_WRITE_DATA_PACKET_POSITION',
    'SHARPEMU_BINK_AUTO_BOOT',
    'SHARPEMU_BINK_AUTO_BOOT_GRACE_MS',
    'SHARPEMU_BINK_BOOT_SEQUENCE',
    'SHARPEMU_BINK_STARTUP_COMPLETION_SHIM',
    'SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY',
    'SHARPEMU_RESERVED_HOST_LANES',
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

$previousEnvironment=@{}
foreach($environmentName in $environmentNames){
    $previousEnvironment[$environmentName]=
        [Environment]::GetEnvironmentVariable($environmentName,'Process')
}

try{
    $env:SHARPEMU_WRITE_DATA_PACKET_POSITION='1'

    # Guest owns the movie state machine. This is the important media change.
    $env:SHARPEMU_BINK_AUTO_BOOT='0'
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS='1500'
    $env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM='1'
    Remove-Item Env:SHARPEMU_BINK_BOOT_SEQUENCE -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY -ErrorAction SilentlyContinue

    # Do not carry the separate JobPool lane-packing A/B into this test.
    Remove-Item Env:SHARPEMU_RESERVED_HOST_LANES -ErrorAction SilentlyContinue

    foreach($environmentName in @(
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
        [Environment]::SetEnvironmentVariable(
            $environmentName,'0','Process')
    }

    Write-Host '[V74.0.26.3] RELEASE guest-owned boot + fast WRITE_DATA test.' -ForegroundColor Cyan
    Write-Host '[V74.0.26.3] Host auto boot is OFF. The EBOOT must naturally request PlayStation Studios; therefore no duplicate-preboot path exists.' -ForegroundColor Cyan
    Write-Host '[V74.0.26.3] Close SharpEmu when LANGUAGE SELECT or another interactive UI appears.' -ForegroundColor Cyan

    $stopwatch=[Diagnostics.Stopwatch]::StartNew()
    $processObject=Start-Process `
        -FilePath $launchFile `
        -ArgumentList $launchArguments `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $processObject.WaitForExit()
    $processObject.WaitForExit()
    $stopwatch.Stop()

    try{
        $exitCode=$processObject.ExitCode
    } catch {
        $exitCode='unavailable'
    }

    $wallSeconds=[Math]::Round(
        $stopwatch.Elapsed.TotalSeconds,
        3)
}
finally{
    foreach($environmentName in $environmentNames){
        if($null -eq $previousEnvironment[$environmentName]){
            Remove-Item ('Env:'+$environmentName) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $environmentName,
                [string]$previousEnvironment[$environmentName],
                'Process')
        }
    }
}

$stdoutLines=@()
$stderrLines=@()
if([IO.File]::Exists($stdout)){
    $stdoutLines=@([IO.File]::ReadAllLines($stdout))
}
if([IO.File]::Exists($stderr)){
    $stderrLines=@([IO.File]::ReadAllLines($stderr))
}

function Find-LinesV740263 {
    param(
        [string[]]$Lines,
        [string]$Needle
    )
    return @($Lines|Where-Object{
        $_.IndexOf(
            $Needle,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
}

$autoBootOrder=@(Find-LinesV740263 $stderrLines 'bink2.auto_boot_order')
$directBoot=@(Find-LinesV740263 $stderrLines 'bink2.direct_boot_')
$naturalMovies=@(Find-LinesV740263 $stderrLines 'bink2.natural_guest_movie_observed')
$binkAttached=@($stderrLines|Where-Object{
    $_ -match 'Bink RAD bridge attached: ([^ ]+\.bk2)'
})
$binkCompleted=@($stderrLines|Where-Object{
    $_ -match 'Bink RAD bridge completed: ([^ ]+\.bk2)'
})
$psStudiosAttached=@($stderrLines|Where-Object{
    $_ -match 'Bink RAD bridge attached: ps_studios_logo\.bk2'
})
$psStudiosCompleted=@($stderrLines|Where-Object{
    $_ -match 'Bink RAD bridge completed: ps_studios_logo\.bk2'
})

$waitLines=@(Find-LinesV740263 $stderrLines '[V74.0.25][WAIT_RESUME]')
$writePosition=@(Find-LinesV740263 $stderrLines '[V74.0.25][WRITE_DATA_PACKET_POSITION]')
$guestFrames=@(Find-LinesV740263 $stderrLines 'Vulkan VideoOut presented guest frame')
$mainLoop=@(Find-LinesV740263 $stdoutLines 'Starting main loop')
$gather=@(Find-LinesV740263 $stdoutLines 'ResourcePool::GatherResourceFileInfo')
$unresolved=@(Find-LinesV740263 $stderrLines 'unresolved:')
$deviceLost=@(Find-LinesV740263 $stderrLines 'deviceLost=True')

$waitValues=New-Object 'Collections.Generic.List[double]'
foreach($line in $waitLines){
    if($line -match 'waited_ms=([0-9]+[\.,][0-9]+)'){
        $value=[double]::Parse(
            $matches[1].Replace(',','.'),
            [Globalization.CultureInfo]::InvariantCulture)
        $waitValues.Add($value)
    }
}

$waitMax=if($waitValues.Count -gt 0){
    ($waitValues|Measure-Object -Maximum).Maximum
} else {0.0}
$waitAverage=if($waitValues.Count -gt 0){
    ($waitValues|Measure-Object -Average).Average
} else {0.0}
$waitOver1s=@($waitValues|Where-Object{$_ -ge 1000.0}).Count
$waitOver4s=@($waitValues|Where-Object{$_ -ge 4000.0}).Count

foreach($pair in @(
    @('AUTO_BOOT_ORDER.txt',$autoBootOrder),
    @('DIRECT_BOOT.txt',$directBoot),
    @('NATURAL_GUEST_MOVIES.txt',$naturalMovies),
    @('BINK_ATTACHED.txt',$binkAttached),
    @('BINK_COMPLETED.txt',$binkCompleted),
    @('PS_STUDIOS_ATTACHED.txt',$psStudiosAttached),
    @('PS_STUDIOS_COMPLETED.txt',$psStudiosCompleted),
    @('WAIT_RESUME.txt',$waitLines),
    @('WRITE_DATA_PACKET_POSITION.txt',$writePosition)
)){
    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($out,$pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=74.0.26.3',
    'mode=guest-owned-media+write-data-packet-position-no-gpu-readback',
    'host_auto_boot=OFF',
    'guest_replay_dedupe=NOT_NEEDED',
    "wall_seconds=$wallSeconds",
    "exit_code=$exitCode",
    "stderr_lines=$($stderrLines.Count)",
    "stdout_lines=$($stdoutLines.Count)",
    "agc_sha256=$agcHash",
    "host_movie_sha256=$((Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash)",
    "auto_boot_order_reports=$($autoBootOrder.Count)",
    "direct_boot_markers=$($directBoot.Count)",
    "natural_guest_movie_count=$($naturalMovies.Count)",
    "bink_attach_count=$($binkAttached.Count)",
    "bink_completed_count=$($binkCompleted.Count)",
    "ps_studios_attach_count=$($psStudiosAttached.Count)",
    "ps_studios_completed_count=$($psStudiosCompleted.Count)",
    "write_data_packet_position_logs=$($writePosition.Count)",
    "wait_resume_logs=$($waitLines.Count)",
    "wait_max_ms=$([Math]::Round([double]$waitMax,3))",
    "wait_avg_ms=$([Math]::Round([double]$waitAverage,3))",
    "wait_over_1s=$waitOver1s",
    "wait_over_4s=$waitOver4s",
    "guest_frames=$($guestFrames.Count)",
    "main_loop=$($mainLoop.Count)",
    "gather_resource=$($gather.Count)",
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

Write-Host "[V74.0.26.3] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
