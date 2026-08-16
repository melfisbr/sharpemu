param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
if(-not(Test-ContainsOrdinal -Text ([IO.File]::ReadAllText($sampler)) -Pattern 'SHARPEMU_TRACE_DEMONS_SCRIPT_LOADER')){
    throw '[V73.12] Diagnostic refused: script-package probe is not installed.'
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw('[V73.12] EBOOT missing: {0}' -f $Eboot)}
$expected='22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($actual -ne $expected){throw('[V73.12] Wrong EBOOT. expected={0} actual={1}' -f $expected,$actual)}

$exe=$null
foreach($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw '[V73.12] SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root ('SharpEmu_V73_12_SCRIPT_PACKAGE_REACHABILITY_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_TRACE_DEMONS_SCRIPT_LOADER',
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
    'SHARPEMU_PROFILE_GUEST_RIP',
    'SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS',
    'SHARPEMU_PROFILE_GUEST_RIP_REPORT_S',
    'SHARPEMU_LOG_VIDEOOUT_FPS',
    'SHARPEMU_LOG_IO',
    'SHARPEMU_LOG_IO_FILTER',
    'SHARPEMU_LOG_AMPR_READS',
    'SHARPEMU_AUTO_OPTIONS',
    'SHARPEMU_SCANOUT_RECOVERY',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_LABEL_PROVENANCE'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try{
    $env:SHARPEMU_TRACE_DEMONS_SCRIPT_LOADER='1'
    $env:SHARPEMU_TRACE_DEMONS_UI_METHODS='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS='2'
    $env:SHARPEMU_PROFILE_GUEST_RIP_REPORT_S='5'
    $env:SHARPEMU_LOG_VIDEOOUT_FPS='1'
    $env:SHARPEMU_LOG_IO='1'
    $env:SHARPEMU_LOG_IO_FILTER='scripts'
    $env:SHARPEMU_LOG_AMPR_READS='1'
    $env:SHARPEMU_AUTO_OPTIONS='150,180,210,240,270,300,330,360'
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

    Write-Host '[V73.12] Starting EBOOT script-package/UI reachability run.'
    Write-Host '[V73.12] Hard ceiling: 480 seconds.'
    Write-Host '[V73.12] After successful uistartmenu.cgpr full read, keep 90 seconds of post-read observation.'

    $p=Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $hard=[DateTime]::UtcNow.AddSeconds(480)
    $menuSeenAt=$null
    while(-not $p.HasExited -and [DateTime]::UtcNow -lt $hard){
        Start-Sleep -Milliseconds 500
        $p.Refresh()

        if($null -eq $menuSeenAt -and (Test-Path -LiteralPath $stderr -PathType Leaf)){
            try{
                $text=[IO.File]::ReadAllText($stderr)
                if(
                    $text.IndexOf('uistartmenu.cgpr',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
                    $text.IndexOf('read=0x000000000017A7D0',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
                    $text.IndexOf('result=0x00000000',[StringComparison]::OrdinalIgnoreCase)-ge 0
                ){
                    $menuSeenAt=[DateTime]::UtcNow
                    Write-Host '[V73.12] Full uistartmenu.cgpr read observed; 90-second post-read window started.'
                }
            }catch{}
        }

        if($null -ne $menuSeenAt -and [DateTime]::UtcNow -ge $menuSeenAt.AddSeconds(90)){
            Write-Host '[V73.12] Post-read observation complete.'
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

$err=@()
$outLines=@()
if(Test-Path -LiteralPath $stderr -PathType Leaf){$err=@([IO.File]::ReadAllLines($stderr))}
if(Test-Path -LiteralPath $stdout -PathType Leaf){$outLines=@([IO.File]::ReadAllLines($stdout))}

function Pick([string]$needle){
    $r=New-Object System.Collections.Generic.List[string]
    foreach($line in $err){
        if($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){$r.Add($line)}
    }
    return $r.ToArray()
}

$scriptHits=@(Pick '[V73.12][SCRIPT_RIP] first_hit')
$scriptCounts=@(Pick '[V73.12][SCRIPT_RIP] counts')
$uiHits=@(Pick '[V73.9][UI_RIP] first_hit')
$uiCounts=@(Pick '[V73.9][UI_RIP] counts')
$menuRead=@(
    $err|Where-Object{
        $_.IndexOf('ampr.read_file:',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('uistartmenu.cgpr',[StringComparison]::OrdinalIgnoreCase)-ge 0
    }
)
$menuReadOk=@(
    $menuRead|Where-Object{
        $_.IndexOf('read=0x000000000017A7D0',[StringComparison]::OrdinalIgnoreCase)-ge 0 -and
        $_.IndexOf('result=0x00000000',[StringComparison]::OrdinalIgnoreCase)-ge 0
    }
)
$fps=@(Pick '[LOADER][PERF] videoout submitted_fps=')
$options=@(Pick '[STARTMENU][AUTO_OPTIONS][V2.1.0]')
$unresolved=@(Pick 'unresolved:')
$deviceLost=@(Pick 'deviceLost=True')

$names=@(
    'StartScriptRoot',
    'ScriptPackagePrimary',
    'ScriptPackageCommonApply',
    'FinalizeGameObjectsJob',
    'CreateGameObjects',
    'ScriptPackageAutoLoadApply',
    'LoadScriptRegion',
    'ScriptPackageManualLoadApply',
    'StartMenuLoaderSourceRegion',
    'IsSceneFullyLoadedExact',
    'ShowHUDSceneImplExact',
    'AdvanceMenuTransitionsExact'
)
$max=@{}
foreach($n in $names){$max[$n]=0L}
foreach($line in $scriptCounts){
    foreach($n in $names){
        $m=[regex]::Match($line,'\b'+[regex]::Escape($n)+'=(\d+)')
        if(-not $m.Success){continue}
        $v=0L
        if([long]::TryParse($m.Groups[1].Value,[ref]$v) -and $v -gt $max[$n]){$max[$n]=$v}
    }
}

$loaderTotal=
    $max['StartScriptRoot']+
    $max['ScriptPackagePrimary']+
    $max['ScriptPackageCommonApply']+
    $max['FinalizeGameObjectsJob']+
    $max['CreateGameObjects']+
    $max['ScriptPackageAutoLoadApply']+
    $max['LoadScriptRegion']+
    $max['ScriptPackageManualLoadApply']+
    $max['StartMenuLoaderSourceRegion']

$uiTransitionTotal=
    $max['IsSceneFullyLoadedExact']+
    $max['ShowHUDSceneImplExact']+
    $max['AdvanceMenuTransitionsExact']

$classification='script-package-probe-inconclusive'
if($menuReadOk.Count -eq 0){
    $classification='uistartmenu-full-read-not-observed'
}elseif($max['StartMenuLoaderSourceRegion'] -gt 0 -and $uiTransitionTotal -gt 0){
    $classification='startmenu-loader-and-ui-transition-execute'
}elseif($max['StartMenuLoaderSourceRegion'] -gt 0){
    $classification='startmenu-loader-executes-ui-transition-not-observed'
}elseif($loaderTotal -gt 0 -and $uiTransitionTotal -gt 0){
    $classification='script-package-and-ui-manager-execute-startmenu-loader-not-observed'
}elseif($loaderTotal -gt 0){
    $classification='script-package-executes-startmenu-ui-not-observed'
}else{
    $classification='menu-read-complete-script-package-native-code-not-observed'
}

Write-Utf8Lines -Path (Join-Path $out 'SCRIPT_RIP_FIRST_HITS.txt') -Lines $scriptHits
Write-Utf8Lines -Path (Join-Path $out 'SCRIPT_RIP_COUNTS.txt') -Lines $scriptCounts
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_FIRST_HITS.txt') -Lines $uiHits
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_COUNTS.txt') -Lines $uiCounts
Write-Utf8Lines -Path (Join-Path $out 'UISTARTMENU_READ.txt') -Lines $menuRead
Write-Utf8Lines -Path (Join-Path $out 'VIDEOOUT_FPS.txt') -Lines $fps
Write-Utf8Lines -Path (Join-Path $out 'AUTO_OPTIONS.txt') -Lines $options

$summary=New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.12')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actual))
$summary.Add(('uistartmenu_full_success={0}' -f $menuReadOk.Count))
foreach($n in $names){$summary.Add(('native_{0}={1}' -f $n,$max[$n]))}
$summary.Add(('script_loader_total_samples={0}' -f $loaderTotal))
$summary.Add(('ui_transition_total_samples={0}' -f $uiTransitionTotal))
$summary.Add(('script_first_hits={0}' -f $scriptHits.Count))
$summary.Add(('ui_first_hits={0}' -f $uiHits.Count))
$summary.Add(('auto_options_lines={0}' -f $options.Count))
$summary.Add(('videoout_fps_windows={0}' -f $fps.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

$pkg=Get-PackageRoot
Copy-Item -LiteralPath (Join-Path $pkg 'evidence\EBOOT_SCRIPT_UI_NATIVE_RANGES.csv') -Destination $out -Force
Copy-Item -LiteralPath (Join-Path $pkg 'evidence\V73_11_1_SUMMARY.txt') -Destination $out -Force

$sourceDir=Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
foreach($relative in @(
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs',
    'src\SharpEmu.Libs\Ampr\AmprExports.cs',
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
Write-Host ('[V73.12] RESULT: {0}' -f $zip)
Write-Host ('[V73.12] classification={0}' -f $classification)
Write-Host ('[V73.12] menu_ok={0}; loader_samples={1}; startmenu_loader={2}; ui_transition_samples={3}' -f
    $menuReadOk.Count,$loaderTotal,$max['StartMenuLoaderSourceRegion'],$uiTransitionTotal)
