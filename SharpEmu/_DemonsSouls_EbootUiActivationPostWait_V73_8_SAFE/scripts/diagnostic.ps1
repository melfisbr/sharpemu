param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw('[V73.8] EBOOT missing: {0}' -f $Eboot)}
$expected='22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($actual -ne $expected){throw('[V73.8] Wrong EBOOT. expected={0} actual={1}' -f $expected,$actual)}

$exe=$null
foreach($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw '[V73.8] SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root ('SharpEmu_V73_8_UI_ACTIVATION_POSTWAIT_RESULT_{0}' -f $stamp)
$sourceDir=Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $out|Out-Null
New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_AUTO_OPTIONS',
    'SHARPEMU_SCANOUT_RECOVERY',
    'SHARPEMU_LOG_IO',
    'SHARPEMU_LOG_AMPR_READS',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_DRAWS',
    'SHARPEMU_TRACE_FRAME_PACKETS',
    'SHARPEMU_RENDER_CHECKPOINTS'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try{
    # Main loop was reached around 75 s in V73.7.1. Multiple one-sample edges
    # cover the entire UI-load window without requiring user input.
    $env:SHARPEMU_AUTO_OPTIONS='90,105,120,135,150'
    $env:SHARPEMU_TRACE_LABEL_PROVENANCE='1'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    foreach($v in @(
        'SHARPEMU_LOG_IO',
        'SHARPEMU_LOG_AMPR_READS',
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_RESOURCES',
        'SHARPEMU_TRACE_DRAWS',
        'SHARPEMU_TRACE_FRAME_PACKETS',
        'SHARPEMU_RENDER_CHECKPOINTS'
    )){
        Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
    }

    Write-Host '[V73.8] Starting EBOOT-specific UI activation + post-UI wait diagnostic.'
    Write-Host '[V73.8] Auto Options edges: 90,105,120,135,150 seconds.'
    Write-Host '[V73.8] Keep the emulator open until at least 155 seconds from launch, then close it.'
    Write-Host '[V73.8] Resource IO tracing is OFF because V73.7.1 already proved it clean.'

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

$outLines=@()
$errLines=@()
if(Test-Path -LiteralPath $stdout -PathType Leaf){$outLines=@([IO.File]::ReadAllLines($stdout))}
if(Test-Path -LiteralPath $stderr -PathType Leaf){$errLines=@([IO.File]::ReadAllLines($stderr))}

function Pick([string]$needle){
    $r=New-Object System.Collections.Generic.List[string]
    foreach($line in $errLines){
        if($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){$r.Add($line)}
    }
    return $r.ToArray()
}

$optionsPress=@(Pick '[STARTMENU][AUTO_OPTIONS][V2.1.0] press')
$optionsRelease=@(Pick '[STARTMENU][AUTO_OPTIONS][V2.1.0] release')
$waitTargets=@(Pick '[V73.4][LABEL] wait_target')
$pm4=@(Pick 'source=pm4_producer_registered')
$writeApplied=@(Pick 'write_data_applied')
$waitResumed=@(Pick '[V73.4][LABEL] wait_resumed')
$waitSuspended=@(Pick 'agc.wait_suspended')
$frames=@(Pick 'Vulkan VideoOut presented guest frame')
$scanout=@(Pick 'agc.scanout_lineage')
$presentRejected=@(Pick 'vk.guest_present_rejected')
$producerPriority=@(Pick '[V73.0.14][PRODUCER_PRIORITY]')
$waitEscape=@(Pick '[V73.0.14][WAIT_ESCAPE]')
$backpressure=@(Pick 'vk.guest_queue_backpressure')
$fences=@(Pick 'vk.ordered_action_fence_wait')
$unresolved=@(Pick 'unresolved:')
$deviceLost=@(Pick 'deviceLost=True')

$classification='ui-path-undetermined'
if($optionsPress.Count -eq 0){
    $classification='options-not-sampled-by-guest'
}elseif($frames.Count -eq 0 -and $waitTargets.Count -gt 0){
    $classification='options-delivered-post-ui-gpu-wait-stall-before-present'
}elseif($frames.Count -eq 1 -and $waitTargets.Count -gt 0){
    $classification='options-delivered-single-frame-post-ui-wait-stall'
}elseif($frames.Count -gt 1 -and $scanout.Count -gt 0){
    $classification='options-delivered-render-and-scanout-continue-ui-scene-composition-next'
}elseif($frames.Count -gt 1){
    $classification='options-delivered-multiple-frames-no-scanout-lineage'
}

Write-Utf8Lines -Path (Join-Path $out 'AUTO_OPTIONS.txt') -Lines @($optionsPress+$optionsRelease)
Write-Utf8Lines -Path (Join-Path $out 'WAIT_TARGETS.txt') -Lines $waitTargets
Write-Utf8Lines -Path (Join-Path $out 'PM4_PRODUCERS.txt') -Lines $pm4
Write-Utf8Lines -Path (Join-Path $out 'WRITEDATA_APPLIED.txt') -Lines $writeApplied
Write-Utf8Lines -Path (Join-Path $out 'WAIT_RESUMED.txt') -Lines $waitResumed
Write-Utf8Lines -Path (Join-Path $out 'WAIT_SUSPENDED.txt') -Lines $waitSuspended
Write-Utf8Lines -Path (Join-Path $out 'GUEST_FRAMES.txt') -Lines $frames
Write-Utf8Lines -Path (Join-Path $out 'SCANOUT_LINEAGE.txt') -Lines $scanout
Write-Utf8Lines -Path (Join-Path $out 'PRESENT_REJECTED.txt') -Lines $presentRejected
Write-Utf8Lines -Path (Join-Path $out 'PRODUCER_PRIORITY.txt') -Lines $producerPriority
Write-Utf8Lines -Path (Join-Path $out 'WAIT_ESCAPE.txt') -Lines $waitEscape

$summary=New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.8')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actual))
$summary.Add(('auto_options_press={0}' -f $optionsPress.Count))
$summary.Add(('auto_options_release={0}' -f $optionsRelease.Count))
$summary.Add(('wait_targets={0}' -f $waitTargets.Count))
$summary.Add(('pm4_producer_overlaps={0}' -f $pm4.Count))
$summary.Add(('write_data_applied={0}' -f $writeApplied.Count))
$summary.Add(('wait_resumed_trace={0}' -f $waitResumed.Count))
$summary.Add(('wait_suspended={0}' -f $waitSuspended.Count))
$summary.Add(('guest_frames={0}' -f $frames.Count))
$summary.Add(('scanout_lineage={0}' -f $scanout.Count))
$summary.Add(('present_rejected={0}' -f $presentRejected.Count))
$summary.Add(('producer_priority_samples={0}' -f $producerPriority.Count))
$summary.Add(('wait_escape_samples={0}' -f $waitEscape.Count))
$summary.Add(('backpressure_samples={0}' -f $backpressure.Count))
$summary.Add(('ordered_fence_max_counter={0}' -f (Get-MaxCounterFromLines -Lines $fences -Field 'count')))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

# Copy exact current sources needed for V73.9.
foreach($relative in @(
    'src\SharpEmu.Libs\Agc\AgcExports.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
    'src\SharpEmu.Libs\VideoOut\VideoOutExports.cs',
    'src\SharpEmu.Libs\Pad\PadExports.cs',
    'src\SharpEmu.Libs\Pad\KeyboardPadMapping.cs',
    'src\SharpEmu.Libs\Media\HostOptionsSkipBridgeV6113262.cs',
    'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
)){
    $source=Join-Path $root $relative
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){continue}
    $dest=Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)|Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

foreach($name in @(
    'EBOOT_UI_NATIVE_METHODS.csv',
    'POST_UI_WAIT_REG_MEM.csv',
    'V73_7_1_POST_UI_RUNTIME.txt'
)){
    Copy-Item -LiteralPath (Join-Path $pkg ('evidence\'+$name)) -Destination $out -Force
}

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host ('[V73.8] RESULT: {0}' -f $zip)
Write-Host ('[V73.8] classification={0}' -f $classification)
Write-Host ('[V73.8] Options={0}/{1}; waits targets/resumed={2}/{3}; frames={4}; scanout={5}; fence_max={6}' -f
    $optionsPress.Count,$optionsRelease.Count,$waitTargets.Count,$waitResumed.Count,$frames.Count,$scanout.Count,(Get-MaxCounterFromLines -Lines $fences -Field 'count'))
