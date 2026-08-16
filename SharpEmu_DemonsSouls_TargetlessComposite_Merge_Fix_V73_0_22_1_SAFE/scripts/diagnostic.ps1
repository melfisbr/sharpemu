param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Resolve-RepoRootV730221 -RepositoryRoot $RepositoryRoot
$agc=Get-AgcPathV730221 -Root $repo
$presenter=Get-PresenterPathV730221 -Root $repo
$state=Get-CompositeMergeStateV730221 -Text ([IO.File]::ReadAllText($agc))
if($state -ne 'Applied'){
    throw "[V73.0.22.1] Composite merge is not installed: $state"
}

$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "[V73.0.22.1] EBOOT SHA256 mismatch: $eh"
}

$releaseRoot=[IO.Path]::Combine(
    $repo,'artifacts','bin','Release','net10.0','win-x64')
$exe=[IO.Path]::Combine($releaseRoot,'SharpEmu.exe')
$dll=[IO.Path]::Combine($releaseRoot,'SharpEmu.dll')

if([IO.File]::Exists($exe)){
    $file=$exe
    $arguments=@($Eboot)
} elseif([IO.File]::Exists($dll)){
    $file='dotnet'
    $arguments=@($dll,$Eboot)
} else {
    throw '[V73.0.22.1] Release SharpEmu executable/DLL not found.'
}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=[IO.Path]::Combine(
    $repo,
    "SharpEmu_V73_0_22_1_TARGETLESS_UI_LOWTRACE_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out) | Out-Null

$stdout=[IO.Path]::Combine($out,'stdout.log')
$stderr=[IO.Path]::Combine($out,'stderr.log')

[IO.File]::Copy(
    $agc,
    [IO.Path]::Combine($out,'AgcExports_CURRENT.cs'),
    $true)
if([IO.File]::Exists($presenter)){
    [IO.File]::Copy(
        $presenter,
        [IO.Path]::Combine($out,'VulkanVideoPresenter_CURRENT.cs'),
        $true)
}

$vars=@(
    'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',
    'SHARPEMU_WRITE_DATA_PACKET_POSITION',
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
foreach($v in $vars){
    $old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')
}

try{
    # Do NOT force the old A/B replay switch. The source merge itself must make
    # PPSA01341 replay the required targetless composites.
    Remove-Item Env:SHARPEMU_REPLAY_TARGETLESS_COMPOSITES -ErrorAction SilentlyContinue

    # Preserve the latest V74.0.25 startup-wait recovery path during this run.
    $env:SHARPEMU_WRITE_DATA_PACKET_POSITION='1'

    # Low-volume timing run.
    $env:SHARPEMU_LOG_AGC='0'
    $env:SHARPEMU_LOG_AGC_SHADER='0'
    $env:SHARPEMU_LOG_VK_SHADER='0'
    $env:SHARPEMU_LOG_VK_COMPUTE_RESOURCES='0'
    $env:SHARPEMU_TRACE_RENDER_WORK='0'
    $env:SHARPEMU_TRACE_ORDERED_ACTION_LATENCY='0'
    $env:SHARPEMU_TRACE_DCC_ALIAS='0'
    $env:SHARPEMU_TRACE_GUEST_IMAGES='0'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='0'
    $env:SHARPEMU_PROFILE_RENDER='0'
    $env:SHARPEMU_PERF_MEM='0'
    $env:SHARPEMU_OVERLAY='0'

    Write-Host '[V73.0.22.1] LOW-TRACE RELEASE run.' -ForegroundColor Cyan
    Write-Host '[V73.0.22.1] Composite replay env override is UNSET; PPSA01341 source rule must produce the UI.' -ForegroundColor Cyan
    Write-Host '[V73.0.22.1] V74.0.25 WRITE_DATA packet-position is enabled to preserve the latest startup-wait recovery.' -ForegroundColor Cyan
    Write-Host '[V73.0.22.1] Close SharpEmu as soon as LANGUAGE SELECT or another interactive UI appears.' -ForegroundColor Cyan

    $sw=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process `
        -FilePath $file `
        -ArgumentList $arguments `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $p.WaitForExit()
    $p.WaitForExit()
    $sw.Stop()

    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
    $wall=[Math]::Round($sw.Elapsed.TotalSeconds,3)
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
if([IO.File]::Exists($stdout)){$so=@([IO.File]::ReadAllLines($stdout))}
if([IO.File]::Exists($stderr)){$se=@([IO.File]::ReadAllLines($stderr))}

function Match-V730221([string[]]$Lines,[string]$Needle){
    return @($Lines | Where-Object {
        $_.IndexOf(
            $Needle,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
}

$writePosition=@(Match-V730221 $se '[V74.0.25][WRITE_DATA_PACKET_POSITION]')
$waitResume=@(Match-V730221 $se '[V74.0.25][WAIT_RESUME]')
$flip=@(Match-V730221 $se '[V16][CP4_FLIP]')
$present=@(Match-V730221 $se '[V16][CP5_PRESENT]')
$guest=@(Match-V730221 $se 'Vulkan VideoOut presented guest frame')
$unresolved=@(Match-V730221 $se 'unresolved:')
$deviceLost=@(Match-V730221 $se 'deviceLost=True')
$mainLoop=@(Match-V730221 $so 'Starting main loop')
$gather=@(Match-V730221 $so 'ResourcePool::GatherResourceFileInfo')
$binkCompleted=@(Match-V730221 $se 'BINK_COMPLETED')

foreach($pair in @(
    @('WRITE_DATA_PACKET_POSITION.txt',$writePosition),
    @('WAIT_RESUME.txt',$waitResume),
    @('FLIPS.txt',$flip),
    @('PRESENTS.txt',$present),
    @('MAIN_LOOP.txt',$mainLoop),
    @('GATHER.txt',$gather),
    @('BINK_COMPLETED.txt',$binkCompleted)
)){
    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($out,$pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false))
}

$summary=@(
    'version=73.0.22.1',
    'mode=title-scoped-targetless-composite-merge+release-lowtrace+v74025-write-position',
    "eboot_sha256=$eh",
    "agc_sha256=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)",
    "presenter_sha256=$(if([IO.File]::Exists($presenter)){(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash}else{'missing'})",
    "wall_seconds=$wall",
    "exit_code=$exitCode",
    "stderr_lines=$($se.Count)",
    "stdout_lines=$($so.Count)",
    "write_data_packet_position_logs=$($writePosition.Count)",
    "wait_resume_logs=$($waitResume.Count)",
    "flip_checkpoints=$($flip.Count)",
    "cp5_present_success=$(@($present | Where-Object {$_ -match 'result=Success'}).Count)",
    "guest_frames=$($guest.Count)",
    "main_loop=$($mainLoop.Count)",
    "gather_resource=$($gather.Count)",
    "bink_completed=$($binkCompleted.Count)",
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

Write-Host "[V73.0.22.1] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
