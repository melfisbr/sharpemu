param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$direct=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
if(-not(Test-ContainsOrdinal -Text ([IO.File]::ReadAllText($direct)) -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE')){
    throw '[V73.10] Diagnostic refused: usleep scheduler fix is not installed.'
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw('[V73.10] EBOOT missing: {0}' -f $Eboot)}
$expected='22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($actual -ne $expected){throw('[V73.10] Wrong EBOOT. expected={0} actual={1}' -f $expected,$actual)}

$exe=$null
foreach($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw '[V73.10] SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root ('SharpEmu_V73_10_JOB_UI_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_LOG_USLEEP',
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    'SHARPEMU_PROFILE_GUEST_RIP',
    'SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS',
    'SHARPEMU_PROFILE_GUEST_RIP_REPORT_S',
    'SHARPEMU_LOG_VIDEOOUT_FPS',
    'SHARPEMU_AUTO_OPTIONS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_LOG_GUEST_THREADS',
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_LOG_IO',
    'SHARPEMU_LOG_AMPR_READS',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_DRAWS',
    'SHARPEMU_TRACE_FRAME_PACKETS',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try{
    $env:SHARPEMU_LOG_USLEEP='1'
    $env:SHARPEMU_TRACE_DEMONS_UI_METHODS='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP_REPORT_S='5'
    $env:SHARPEMU_LOG_VIDEOOUT_FPS='1'
    $env:SHARPEMU_AUTO_OPTIONS='70,80,90,100,110,120'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_LOG_GUEST_THREADS='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    foreach($v in @(
        'SHARPEMU_TRACE_LABEL_PROVENANCE',
        'SHARPEMU_LOG_IO',
        'SHARPEMU_LOG_AMPR_READS',
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_RESOURCES',
        'SHARPEMU_TRACE_DRAWS',
        'SHARPEMU_TRACE_FRAME_PACKETS'
    )){
        Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
    }

    Write-Host '[V73.10] Starting JobSystem/usleep/UI diagnostic.'
    Write-Host '[V73.10] The script will stop the representative run after 130 seconds if it is still running.'
    Write-Host '[V73.10] sceKernelUsleep HLE trace is sampled; heavy AGC/resource logging remains disabled.'

    $p=Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $deadline=[DateTime]::UtcNow.AddSeconds(130)
    while(-not $p.HasExited -and [DateTime]::UtcNow -lt $deadline){
        Start-Sleep -Milliseconds 250
        $p.Refresh()
    }
    if(-not $p.HasExited){
        Write-Host '[V73.10] 130-second diagnostic window complete; stopping emulator.'
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        $p.WaitForExit()
    }
    try{$exitCode=$p.ExitCode}catch{$exitCode='diagnostic-stop'}
}
finally{
    foreach($v in $vars){
        if($null -eq $old[$v]){Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue}
        else{[Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')}
    }
}

$err=@()
if(Test-Path -LiteralPath $stderr -PathType Leaf){$err=@([IO.File]::ReadAllLines($stderr))}
function Pick([string]$needle){
    $r=New-Object System.Collections.Generic.List[string]
    foreach($line in $err){
        if($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){$r.Add($line)}
    }
    return $r.ToArray()
}

$usleep=@(Pick '[LOADER][TRACE] usleep#')
$uiCounts=@(Pick '[V73.9][UI_RIP] counts')
$uiHits=@(Pick '[V73.9][UI_RIP] first_hit')
$profile=@(Pick '[PERF][GUEST]')
$fps=@(Pick '[LOADER][PERF] videoout submitted_fps=')
$options=@(Pick '[STARTMENU][AUTO_OPTIONS][V2.1.0]')
$scanout=@(Pick 'agc.scanout_lineage')
$unresolved=@(Pick 'unresolved:')
$deviceLost=@(Pick 'deviceLost=True')

$uiNames=@(
    'HasOpenMenus',
    'PrintSceneState',
    'ShowHudSceneRegion',
    'TransitionShowHUDValidate',
    'ShowLegacyMenuA',
    'ShowLegacyMenuB',
    'StartMenuThink',
    'StartMenuHandleInputFocus'
)
$maxUi=@{}
foreach($n in $uiNames){$maxUi[$n]=0L}
foreach($line in $uiCounts){
    foreach($n in $uiNames){
        $m=[regex]::Match($line,'\b'+[regex]::Escape($n)+'=(\d+)')
        if(-not $m.Success){continue}
        $v=0L
        if([long]::TryParse($m.Groups[1].Value,[ref]$v) -and $v -gt $maxUi[$n]){$maxUi[$n]=$v}
    }
}

$page821Max=Get-MaxPageShare821 -Lines $profile
$optionPress=@($options|Where-Object{$_.IndexOf(' press ',[StringComparison]::Ordinal)-ge 0})

$presentedPositive=0
$submittedPositive=0
$maxPresented=0.0
foreach($line in $fps){
    foreach($pair in @(
        @{Name='submitted'; Pattern='submitted_fps=([0-9]+(?:[\.,][0-9]+)?)'},
        @{Name='presented'; Pattern='presented_fps=([0-9]+(?:[\.,][0-9]+)?)'}
    )){
        $m=[regex]::Match($line,$pair.Pattern)
        if(-not $m.Success){continue}
        $txt=$m.Groups[1].Value.Replace(',','.')
        $v=0.0
        if(-not [double]::TryParse($txt,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v)){continue}
        if($pair.Name -eq 'submitted' -and $v -gt 0){$submittedPositive++}
        if($pair.Name -eq 'presented'){
            if($v -gt 0){$presentedPositive++}
            if($v -gt $maxPresented){$maxPresented=$v}
        }
    }
}

$classification='usleep-hle-run-inconclusive'
if($maxUi['StartMenuThink'] -gt 0 -or $maxUi['StartMenuHandleInputFocus'] -gt 0){
    $classification='job-scheduler-hle-progressed-into-startmenu'
}elseif($maxUi['HasOpenMenus'] -gt 0 -or $maxUi['ShowHudSceneRegion'] -gt 0 -or $maxUi['TransitionShowHUDValidate'] -gt 0){
    $classification='job-scheduler-hle-progressed-into-ui-manager'
}elseif($usleep.Count -gt 0 -and $page821Max -lt 60){
    $classification='usleep-hle-reduced-job-wait-spin-ui-still-not-reached'
}elseif($usleep.Count -gt 0 -and $page821Max -ge 60){
    $classification='usleep-hle-active-job-wait-still-dominant'
}

Write-Utf8Lines -Path (Join-Path $out 'USLEEP_HLE_TRACE.txt') -Lines $usleep
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_COUNTS.txt') -Lines $uiCounts
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_FIRST_HITS.txt') -Lines $uiHits
Write-Utf8Lines -Path (Join-Path $out 'GUEST_RIP_PROFILE.txt') -Lines $profile
Write-Utf8Lines -Path (Join-Path $out 'VIDEOOUT_FPS.txt') -Lines $fps
Write-Utf8Lines -Path (Join-Path $out 'AUTO_OPTIONS.txt') -Lines $options
Write-Utf8Lines -Path (Join-Path $out 'SCANOUT_LINEAGE.txt') -Lines $scanout

$summary=New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.10')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actual))
$summary.Add(('usleep_hle_trace_lines={0}' -f $usleep.Count))
$summary.Add(('job_wait_page_821_max_percent={0:F3}' -f $page821Max))
$summary.Add('v73_9_job_wait_page_821_max_percent=91.2')
foreach($n in $uiNames){$summary.Add(('ui_{0}={1}' -f $n,$maxUi[$n]))}
$summary.Add(('auto_options_press={0}' -f $optionPress.Count))
$summary.Add(('videoout_fps_windows={0}' -f $fps.Count))
$summary.Add(('videoout_submitted_positive_windows={0}' -f $submittedPositive))
$summary.Add(('videoout_presented_positive_windows={0}' -f $presentedPositive))
$summary.Add(('videoout_max_presented_fps={0:F3}' -f $maxPresented))
$summary.Add(('scanout_lineage={0}' -f $scanout.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

$pkg=Get-PackageRoot
Copy-Item -LiteralPath (Join-Path $pkg 'evidence\JOB_SYSTEM_EBOOT_PROOF.txt') -Destination $out -Force

$sourceDir=Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
foreach($relative in @(
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs',
    'src\SharpEmu.Libs\Kernel\KernelRuntimeCompatExports.cs'
)){
    $source=Join-Path $root $relative
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){continue}
    $dest=Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)|Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host ('[V73.10] RESULT: {0}' -f $zip)
Write-Host ('[V73.10] classification={0}' -f $classification)
Write-Host ('[V73.10] usleep_hle={0}; job_wait_page_max={1:F1}%; StartMenuThink={2}; HandleInputFocus={3}; Options={4}; submitted/presented windows={5}/{6}' -f
    $usleep.Count,$page821Max,$maxUi['StartMenuThink'],$maxUi['StartMenuHandleInputFocus'],$optionPress.Count,$submittedPositive,$presentedPositive)
