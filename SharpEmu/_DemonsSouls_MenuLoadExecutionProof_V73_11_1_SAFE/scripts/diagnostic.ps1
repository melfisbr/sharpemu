param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw('[V73.11.1] EBOOT missing: {0}' -f $Eboot)
}
$expected='22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($actual -ne $expected){
    throw('[V73.11.1] Wrong EBOOT. expected={0} actual={1}' -f $expected,$actual)
}

$exe=$null
foreach($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw '[V73.11.1] SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root ('SharpEmu_V73_11_1_MENU_LOAD_EXECUTION_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_LOG_IO',
    'SHARPEMU_LOG_IO_FILTER',
    'SHARPEMU_LOG_AMPR_READS',
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    'SHARPEMU_PROFILE_GUEST_RIP',
    'SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS',
    'SHARPEMU_PROFILE_GUEST_RIP_REPORT_S',
    'SHARPEMU_LOG_VIDEOOUT_FPS',
    'SHARPEMU_AUTO_OPTIONS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try{
    # Exact read/resolve evidence for script assets.
    $env:SHARPEMU_LOG_IO='1'
    $env:SHARPEMU_LOG_IO_FILTER='scripts'
    $env:SHARPEMU_LOG_AMPR_READS='1'

    # Keep the already-installed UI reachability probe, but at a lower-impact rate.
    $env:SHARPEMU_TRACE_DEMONS_UI_METHODS='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS='8'
    $env:SHARPEMU_PROFILE_GUEST_RIP_REPORT_S='10'
    $env:SHARPEMU_LOG_VIDEOOUT_FPS='1'
    $env:SHARPEMU_AUTO_OPTIONS='180,210,240,270,300,330'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    foreach($v in @(
        'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_RESOURCES',
        'SHARPEMU_TRACE_LABEL_PROVENANCE'
    )){
        Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
    }

    Write-Host '[V73.11.1] Starting menu-file load/execution proof.'
    Write-Host '[V73.11.1] Hard ceiling: 420 seconds.'
    Write-Host '[V73.11.1] Once a successful full uistartmenu.cgpr read is observed, the run remains open for another 45 seconds.'

    $p=Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $hardDeadline=[DateTime]::UtcNow.AddSeconds(420)
    $menuSeenAt=$null
    while(-not $p.HasExited -and [DateTime]::UtcNow -lt $hardDeadline){
        Start-Sleep -Milliseconds 500
        $p.Refresh()

        if($null -eq $menuSeenAt -and
           (Test-Path -LiteralPath $stderr -PathType Leaf)){
            try{
                $tail=[IO.File]::ReadAllText($stderr)
                if(
                    $tail.IndexOf('uistartmenu.cgpr',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
                    $tail.IndexOf('read=0x000000000017A7D0',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
                    $tail.IndexOf('result=0x00000000',[StringComparison]::OrdinalIgnoreCase)-ge 0
                ){
                    $menuSeenAt=[DateTime]::UtcNow
                    Write-Host '[V73.11.1] Successful full uistartmenu.cgpr read observed; starting 45-second post-menu window.'
                }
            }catch{}
        }

        if($null -ne $menuSeenAt -and
           [DateTime]::UtcNow -ge $menuSeenAt.AddSeconds(45)){
            Write-Host '[V73.11.1] Post-menu observation window complete.'
            break
        }
    }

    if(-not $p.HasExited){
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        try{$p.WaitForExit()}catch{}
    }
    try{$exitCode=$p.ExitCode}catch{$exitCode='diagnostic-stop'}
}
finally{
    foreach($v in $vars){
        if($null -eq $old[$v]){Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue}
        else{[Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')}
    }
}

$err=Read-AllLinesSafe -Path $stderr
$outLines=Read-AllLinesSafe -Path $stdout

function PickErr([string]$needle){
    $r=New-Object System.Collections.Generic.List[string]
    foreach($line in $err){
        if($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){$r.Add($line)}
    }
    return $r.ToArray()
}
function PickOut([string]$needle){
    $r=New-Object System.Collections.Generic.List[string]
    foreach($line in $outLines){
        if($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){$r.Add($line)}
    }
    return $r.ToArray()
}

$menuResolve=@(
    $err |
    Where-Object{
        $_.IndexOf('apr_resolve ',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('uistartmenu.cgpr',[StringComparison]::OrdinalIgnoreCase)-ge 0
    }
)
$menuRead=@(
    $err |
    Where-Object{
        $_.IndexOf('ampr.read_file:',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('uistartmenu.cgpr',[StringComparison]::OrdinalIgnoreCase)-ge 0
    }
)
$menuReadOk=@(
    $menuRead |
    Where-Object{
        $_.IndexOf('size=0x000000000017A7D0',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('read=0x000000000017A7D0',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('result=0x00000000',[StringComparison]::OrdinalIgnoreCase)-ge 0
    }
)

$uiScriptReads=@(
    $err |
    Where-Object{
        $_.IndexOf('ampr.read_file:',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('\ui\scripts\',[StringComparison]::OrdinalIgnoreCase)-ge 0
    }
)
$uiReadFailures=@(
    $uiScriptReads |
    Where-Object{
        $_.IndexOf('result=0x00000000',[StringComparison]::OrdinalIgnoreCase)-lt 0
    }
)

$cp11Start=@(PickOut 'Starting Script: $/scripts/cp11/_cmn/cp11main.cgpr')
$mainLoop=@(PickOut 'Starting main loop:')
$gather=@(PickOut 'ResourcePool::GatherResourceFileInfo()')
$uiCounts=@(PickErr '[V73.9][UI_RIP] counts')
$uiHits=@(PickErr '[V73.9][UI_RIP] first_hit')
$options=@(PickErr '[STARTMENU][AUTO_OPTIONS][V2.1.0]')
$fps=@(PickErr '[LOADER][PERF] videoout submitted_fps=')
$unresolved=@(PickErr 'unresolved:')
$deviceLost=@(PickErr 'deviceLost=True')

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

$classification='menu-load-proof-incomplete'
if($menuResolve.Count -eq 0){
    $classification='menu-file-not-resolved'
}elseif($menuRead.Count -eq 0){
    $classification='menu-resolved-but-read-not-observed'
}elseif($menuReadOk.Count -eq 0){
    $classification='menu-read-observed-but-not-complete-success'
}elseif($maxUi['StartMenuThink'] -gt 0 -or $maxUi['StartMenuHandleInputFocus'] -gt 0){
    $classification='menu-read-complete-startmenu-native-code-reached'
}elseif($maxUi['HasOpenMenus'] -gt 0 -or $maxUi['ShowHudSceneRegion'] -gt 0 -or $maxUi['TransitionShowHUDValidate'] -gt 0){
    $classification='menu-read-complete-ui-manager-native-code-reached'
}else{
    $classification='menu-read-complete-ui-native-code-not-yet-observed'
}

Write-Utf8Lines -Path (Join-Path $out 'UISTARTMENU_RESOLVE.txt') -Lines $menuResolve
Write-Utf8Lines -Path (Join-Path $out 'UISTARTMENU_READ.txt') -Lines $menuRead
Write-Utf8Lines -Path (Join-Path $out 'UI_SCRIPT_READS.txt') -Lines $uiScriptReads
Write-Utf8Lines -Path (Join-Path $out 'UI_SCRIPT_READ_FAILURES.txt') -Lines $uiReadFailures
Write-Utf8Lines -Path (Join-Path $out 'SCRIPT_MILESTONES.txt') -Lines @($cp11Start+$mainLoop+$gather)
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_FIRST_HITS.txt') -Lines $uiHits
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_COUNTS.txt') -Lines $uiCounts
Write-Utf8Lines -Path (Join-Path $out 'AUTO_OPTIONS.txt') -Lines $options
Write-Utf8Lines -Path (Join-Path $out 'VIDEOOUT_FPS.txt') -Lines $fps

$summary=New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.11.1')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actual))
$summary.Add(('uistartmenu_resolve_lines={0}' -f $menuResolve.Count))
$summary.Add(('uistartmenu_read_lines={0}' -f $menuRead.Count))
$summary.Add(('uistartmenu_full_success={0}' -f $menuReadOk.Count))
$summary.Add(('ui_script_reads={0}' -f $uiScriptReads.Count))
$summary.Add(('ui_script_read_failures={0}' -f $uiReadFailures.Count))
$summary.Add(('cp11main_start={0}' -f $cp11Start.Count))
$summary.Add(('main_loop_start={0}' -f $mainLoop.Count))
$summary.Add(('resource_gather={0}' -f $gather.Count))
foreach($n in $uiNames){$summary.Add(('ui_{0}={1}' -f $n,$maxUi[$n]))}
$summary.Add(('auto_options_lines={0}' -f $options.Count))
$summary.Add(('videoout_fps_windows={0}' -f $fps.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

$pkg=Get-PackageRoot
foreach($name in @(
    'V73_7_1_UISTARTMENU_RESOLVE.txt',
    'V73_7_1_UISTARTMENU_READ.txt',
    'V73_7_1_SCRIPT_MILESTONES.txt',
    'DIAGNOSTIC_TIMING_CAUSE.txt'
)){
    Copy-Item -LiteralPath (Join-Path $pkg ('evidence\'+$name)) -Destination $out -Force
}

$sourceDir=Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
foreach($relative in @(
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs',
    'src\SharpEmu.Libs\Ampr\AmprExports.cs',
    'src\SharpEmu.Libs\Ampr\AmprFileRegistry.cs',
    'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs',
    'src\SharpEmu.Libs\Pad\PadExports.cs'
)){
    $source=Join-Path $root $relative
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){continue}
    $dest=Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)|Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host ('[V73.11.1] RESULT: {0}' -f $zip)
Write-Host ('[V73.11.1] classification={0}' -f $classification)
Write-Host ('[V73.11.1] uistartmenu resolve/read/full={0}/{1}/{2}; ui_reads/failures={3}/{4}; cp11/main/gather={5}/{6}/{7}; StartMenuThink={8}' -f
    $menuResolve.Count,$menuRead.Count,$menuReadOk.Count,$uiScriptReads.Count,$uiReadFailures.Count,
    $cp11Start.Count,$mainLoop.Count,$gather.Count,$maxUi['StartMenuThink'])
