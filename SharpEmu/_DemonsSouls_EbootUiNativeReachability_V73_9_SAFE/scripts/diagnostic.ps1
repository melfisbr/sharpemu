param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
if(-not(Test-ContainsOrdinal -Text ([IO.File]::ReadAllText($sampler)) -Pattern 'SHARPEMU_TRACE_DEMONS_UI_METHODS')){
    throw '[V73.9] Diagnostic refused: UI RIP probe is not installed.'
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw('[V73.9] EBOOT missing: {0}' -f $Eboot)}
$expected='22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($actual -ne $expected){throw('[V73.9] Wrong EBOOT. expected={0} actual={1}' -f $expected,$actual)}

$exe=$null
foreach($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw '[V73.9] SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root ('SharpEmu_V73_9_UI_NATIVE_REACHABILITY_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    'SHARPEMU_PROFILE_GUEST_RIP',
    'SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS',
    'SHARPEMU_PROFILE_GUEST_RIP_REPORT_S',
    'SHARPEMU_LOG_VIDEOOUT_FPS',
    'SHARPEMU_AUTO_OPTIONS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
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
    $env:SHARPEMU_TRACE_DEMONS_UI_METHODS='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS='1'
    $env:SHARPEMU_PROFILE_GUEST_RIP_REPORT_S='5'
    $env:SHARPEMU_LOG_VIDEOOUT_FPS='1'
    $env:SHARPEMU_AUTO_OPTIONS='90,105,120,135,150'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
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

    Write-Host '[V73.9] Starting exact EBOOT UI native-method reachability run.'
    Write-Host '[V73.9] Keep the emulator open until at least 160 seconds from launch, then close it.'
    Write-Host '[V73.9] UI RIP sampling=1ms; report=5s; VideoOut FPS counter enabled.'

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

$firstHits=@(Pick '[V73.9][UI_RIP] first_hit')
$countLines=@(Pick '[V73.9][UI_RIP] counts')
$perf=@(Pick '[PERF][GUEST]')
$videoFps=@(Pick '[LOADER][PERF] videoout submitted_fps=')
$options=@(Pick '[STARTMENU][AUTO_OPTIONS][V2.1.0]')
$scanout=@(Pick 'agc.scanout_lineage')
$unresolved=@(Pick 'unresolved:')
$deviceLost=@(Pick 'deviceLost=True')

$names=@(
    'HasOpenMenus',
    'PrintSceneState',
    'ShowHudSceneRegion',
    'TransitionShowHUDValidate',
    'ShowLegacyMenuA',
    'ShowLegacyMenuB',
    'StartMenuThink',
    'StartMenuHandleInputFocus'
)
$maxCounts=@{}
foreach($name in $names){$maxCounts[$name]=0L}
foreach($line in $countLines){
    foreach($name in $names){
        $m=[regex]::Match($line,'\b'+[regex]::Escape($name)+'=(\d+)')
        if($m.Success){
            $v=0L
            if([long]::TryParse($m.Groups[1].Value,[ref]$v) -and $v -gt $maxCounts[$name]){
                $maxCounts[$name]=$v
            }
        }
    }
}

$presentedPositive=0
$maxPresented=0.0
foreach($line in $videoFps){
    $m=[regex]::Match($line,'presented_fps=([0-9]+(?:[\.,][0-9]+)?)')
    if(-not $m.Success){continue}
    $text=$m.Groups[1].Value.Replace(',','.')
    $v=0.0
    if([double]::TryParse(
        $text,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$v)){
        if($v -gt 0){$presentedPositive++}
        if($v -gt $maxPresented){$maxPresented=$v}
    }
}

$optionPress=@($options|Where-Object{$_.IndexOf(' press ',[StringComparison]::Ordinal)-ge 0})

$classification='ui-native-reachability-inconclusive'
if($maxCounts['StartMenuThink'] -gt 0 -and $maxCounts['StartMenuHandleInputFocus'] -gt 0){
    $classification='startmenu-think-and-inputfocus-execute'
}elseif($maxCounts['StartMenuThink'] -gt 0){
    $classification='startmenu-think-executes-focus-handler-not-observed'
}elseif($maxCounts['HasOpenMenus'] -gt 0 -or $maxCounts['ShowHudSceneRegion'] -gt 0 -or $maxCounts['TransitionShowHUDValidate'] -gt 0){
    $classification='ui-manager-active-startmenu-component-not-observed'
}elseif($optionPress.Count -gt 0 -and $countLines.Count -gt 0){
    $classification='options-delivered-ui-native-methods-not-observed'
}

Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_FIRST_HITS.txt') -Lines $firstHits
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_COUNTS.txt') -Lines $countLines
Write-Utf8Lines -Path (Join-Path $out 'GUEST_RIP_PROFILE.txt') -Lines $perf
Write-Utf8Lines -Path (Join-Path $out 'VIDEOOUT_FPS.txt') -Lines $videoFps
Write-Utf8Lines -Path (Join-Path $out 'AUTO_OPTIONS.txt') -Lines $options
Write-Utf8Lines -Path (Join-Path $out 'SCANOUT_LINEAGE.txt') -Lines $scanout

$summary=New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.9')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actual))
foreach($name in $names){$summary.Add(('ui_{0}={1}' -f $name,$maxCounts[$name]))}
$summary.Add(('auto_options_press={0}' -f $optionPress.Count))
$summary.Add(('videoout_fps_windows={0}' -f $videoFps.Count))
$summary.Add(('videoout_presented_positive_windows={0}' -f $presentedPositive))
$summary.Add(('videoout_max_presented_fps={0:F3}' -f $maxPresented))
$summary.Add(('scanout_lineage={0}' -f $scanout.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

$pkg=Get-PackageRoot
Copy-Item -LiteralPath (Join-Path $pkg 'evidence\EBOOT_UI_NATIVE_RANGES.csv') -Destination $out -Force
Copy-Item -LiteralPath (Join-Path $pkg 'evidence\DIAGNOSTIC_CORRECTION.txt') -Destination $out -Force

$sourceDir=Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
foreach($relative in @(
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs',
    'src\SharpEmu.Libs\Pad\PadExports.cs',
    'src\SharpEmu.Libs\VideoOut\VideoOutExports.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
)){
    $source=Join-Path $root $relative
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){continue}
    $dest=Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)|Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host ('[V73.9] RESULT: {0}' -f $zip)
Write-Host ('[V73.9] classification={0}' -f $classification)
Write-Host ('[V73.9] StartMenuThink={0}; HandleInputFocus={1}; HasOpenMenus={2}; Options={3}; positive_present_windows={4}; max_presented_fps={5:F2}' -f
    $maxCounts['StartMenuThink'],
    $maxCounts['StartMenuHandleInputFocus'],
    $maxCounts['HasOpenMenus'],
    $optionPress.Count,
    $presentedPositive,
    $maxPresented)
