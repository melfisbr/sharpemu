param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw('[V73.6] EBOOT missing: {0}' -f $Eboot)
}

$exe=$null
foreach($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$exe=$candidate;break}
}
if($null -eq $exe){throw '[V73.6] SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root ('SharpEmu_V73_6_RENDER_SCANOUT_HANDOFF_RESULT_{0}' -f $stamp)
$sourceDir=Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $out|Out-Null
New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null

$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_RENDER_CHECKPOINTS',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'SHARPEMU_SCANOUT_RECOVERY',
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_DRAWS',
    'SHARPEMU_TRACE_FRAME_PACKETS',
    'SHARPEMU_TRACE_GEOMETRY_DRAWS'
)
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}

try{
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_RENDER_CHECKPOINTS='1'
    $env:SHARPEMU_TRACE_DCC_ALIAS='1'

    # Do not let an inherited shell variable enable an old aggressive recovery.
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    foreach($v in @(
        'SHARPEMU_TRACE_LABEL_PROVENANCE',
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_RESOURCES',
        'SHARPEMU_TRACE_DRAWS',
        'SHARPEMU_TRACE_FRAME_PACKETS',
        'SHARPEMU_TRACE_GEOMETRY_DRAWS'
    )){
        Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
    }

    Write-Host '[V73.6] Starting focused render/scanout/Bink-handoff run.'
    Write-Host '[V73.6] Keep the game open past direct_boot_completed for about 20-30 seconds, then close it.'
    Write-Host '[V73.6] Full AGC/Vulkan logging and label provenance are disabled.'

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
        }else{
            [Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')
        }
    }
}

$stdoutLines=@()
$stderrLines=@()
if(Test-Path -LiteralPath $stdout -PathType Leaf){$stdoutLines=@([IO.File]::ReadAllLines($stdout))}
if(Test-Path -LiteralPath $stderr -PathType Leaf){$stderrLines=@([IO.File]::ReadAllLines($stderr))}

function Pick([string]$needle){
    $list=New-Object System.Collections.Generic.List[string]
    foreach($line in $stderrLines){
        if($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){$list.Add($line)}
    }
    return $list.ToArray()
}

$scanout=@(Pick 'agc.scanout_lineage')
$cpFlip=@(Pick '[V16][CP4_FLIP]')
$rtSampled=@(Pick 'agc.rt_sampled')
$dcc=@(Pick '[V24][DCC]')
$directFlip=@(Pick 'direct_flip')
$guestFrame=@(Pick 'Vulkan VideoOut presented guest frame')
$bootSelected=@(Pick 'bink2.boot_sequence_selected')
$bootCompleted=@(Pick 'bink2.direct_boot_completed')
$bootOrder=@(Pick 'bink2.auto_boot_order')
$binkFrames=@(Pick 'bink2.direct_frame')
$waits=@(Pick 'agc.wait_suspended')
$resumes=@(Pick 'agc.queue_resumed')
$fences=@(Pick 'vk.ordered_action_fence_wait')
$backpressure=@(Pick 'vk.guest_queue_backpressure')
$unresolved=@(Pick 'unresolved:')
$deviceLost=@(Pick 'deviceLost=True')

Write-Utf8Lines -Path (Join-Path $out 'SCANOUT_LINEAGE.txt') -Lines $scanout
Write-Utf8Lines -Path (Join-Path $out 'FLIP_CHECKPOINTS.txt') -Lines $cpFlip
Write-Utf8Lines -Path (Join-Path $out 'RT_SAMPLED.txt') -Lines $rtSampled
Write-Utf8Lines -Path (Join-Path $out 'DCC_ALIAS.txt') -Lines $dcc
Write-Utf8Lines -Path (Join-Path $out 'DIRECT_FLIP.txt') -Lines $directFlip
Write-Utf8Lines -Path (Join-Path $out 'GUEST_FRAMES.txt') -Lines $guestFrame
Write-Utf8Lines -Path (Join-Path $out 'BINK_HANDOFF.txt') -Lines @($bootOrder+$bootSelected+$bootCompleted)

$classification='unknown'
if($bootCompleted.Count -gt 0 -and $cpFlip.Count -eq 0){
    $classification='post-bink-no-agc-flip-packets'
}elseif($cpFlip.Count -gt 0 -and $scanout.Count -eq 0){
    $classification='flip-packets-display-buffer-unresolved'
}elseif($scanout.Count -gt 0 -and $guestFrame.Count -eq 0){
    $classification='flip-lineage-present-but-no-guest-frame'
}elseif($guestFrame.Count -gt 0){
    $classification='guest-frame-presentation-reached'
}

$summary=New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.6')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('boot_sequence_selected={0}' -f $bootSelected.Count))
$summary.Add(('direct_boot_completed={0}' -f $bootCompleted.Count))
$summary.Add(('flip_checkpoints={0}' -f $cpFlip.Count))
$summary.Add(('scanout_lineage={0}' -f $scanout.Count))
$summary.Add(('guest_frames={0}' -f $guestFrame.Count))
$summary.Add(('rt_sampled={0}' -f $rtSampled.Count))
$summary.Add(('dcc_alias_lines={0}' -f $dcc.Count))
$summary.Add(('direct_flip_lines={0}' -f $directFlip.Count))
$summary.Add(('wait_suspended={0}' -f $waits.Count))
$summary.Add(('queue_resumed={0}' -f $resumes.Count))
$summary.Add(('ordered_fence_samples={0}' -f $fences.Count))
$summary.Add(('backpressure_samples={0}' -f $backpressure.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

# Collect exact current source needed to decide the next semantic fix.
$sourceRelative=@(
    'src\SharpEmu.Libs\Agc\AgcExports.cs',
    'src\SharpEmu.Libs\VideoOut\VideoOutExports.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
    'src\SharpEmu.Libs\Media\HostMovieBridge.cs',
    'src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs',
    'src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
)
$sourceHashes=New-Object System.Collections.Generic.List[string]
foreach($relative in $sourceRelative){
    $source=Join-Path $root $relative
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){
        $sourceHashes.Add(('MISSING  {0}' -f $relative))
        continue
    }
    $destination=Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $sourceHashes.Add(('{0}  {1}' -f (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash,$relative))
}
Write-Utf8Lines -Path (Join-Path $out 'SOURCE_SHA256.txt') -Lines $sourceHashes

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force

Write-Host ('[V73.6] RESULT: {0}' -f $zip)
Write-Host ('[V73.6] classification={0}' -f $classification)
Write-Host ('[V73.6] flip={0} scanout={1} guest_frames={2} rt_sampled={3} dcc={4}' -f $cpFlip.Count,$scanout.Count,$guestFrame.Count,$rtSampled.Count,$dcc.Count)
