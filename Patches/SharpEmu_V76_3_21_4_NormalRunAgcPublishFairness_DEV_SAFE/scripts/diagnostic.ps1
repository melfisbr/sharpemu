param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Fail "Debug exe ausente: $exe" }
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { Fail "eboot ausente: $game" }
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Deliberately LOW overhead. V21.3.1.1.2 proved that geometry/thread snapshot
# diagnostics materially change timing and can hide the normal-run race.
$env:SHARPEMU_BINK_AUTO_BOOT='0'
Remove-Item Env:\SHARPEMU_BINK_BOOT_SEQUENCE -ErrorAction SilentlyContinue
$env:SHARPEMU_V763214_DISABLE='0'
$env:SHARPEMU_TRACE_SCENE_PIPELINE_GAPS='0'
$env:SHARPEMU_TRACE_GEOMETRY_DRAWS='0'
$env:SHARPEMU_TRACE_PRIMITIVE_PIPELINE='0'
$env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS='0'
$env:SHARPEMU_PERIODIC_SNAPSHOT_SECONDS='0'
$env:SHARPEMU_PROFILE_RENDER='1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='0'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S='10'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $Patches "V76.3.21.4_STDOUT_$stamp.log"
$stderr=Join-Path $Patches "V76.3.21.4_STDERR_$stamp.log"
$summary=Join-Path $Patches "V76.3.21.4_SUMMARY_$stamp.txt"
$result=Join-Path $Patches "V76.3.21.4_RESULT_$stamp.zip"
$start=Get-Date
$p=Start-Process -FilePath $exe -ArgumentList @($game) -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$deadline=$start.AddSeconds(210); $naturalSeenAt=$null
while(-not $p.HasExited -and (Get-Date) -lt $deadline){
  Start-Sleep -Milliseconds 500
  if(-not $naturalSeenAt -and (Test-Path -LiteralPath $stderr)){
    $hit=Select-String -LiteralPath $stderr -Pattern "NATURAL-REQUEST.*file='ps_studios_logo\.bk2'|natural_guest_movie_observed.*file='ps_studios_logo\.bk2'" -Quiet -ErrorAction SilentlyContinue
    if($hit){$naturalSeenAt=Get-Date}
  }
  if($naturalSeenAt -and (Get-Date) -ge $naturalSeenAt.AddSeconds(15)){break}
}
$exitCode=''
if(-not $p.HasExited){ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; try{$p.WaitForExit()}catch{} }
else { try{$p.WaitForExit();$exitCode=$p.ExitCode}catch{} }
$out=if(Test-Path $stdout){@(Get-Content $stdout)}else{@()}
$err=if(Test-Path $stderr){@(Get-Content $stderr)}else{@()}

function Get-MaxLong([object[]]$Lines,[string]$Pattern){$max=0L;foreach($line in $Lines){$m=[regex]::Match($line,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase);if($m.Success){$v=0L;if([long]::TryParse($m.Groups[1].Value,[ref]$v)-and $v -gt $max){$max=$v}}};return $max}
$profile=@($err|Where-Object{$_ -match '\[V76\.3\.21\.4\]\[AGC_PUBLISH_FAIRNESS\]'})
$meaning=@($err|Where-Object{$_ -match '\[V76\.3\.21\.4\]\[AGC_MEANINGFUL_PROGRESS\]'})
$builder=@($meaning|Where-Object{$_ -match 'phase=builder'})
$submit=@($meaning|Where-Object{$_ -match 'phase=submit'})
$natural=@($err|Where-Object{$_ -match "NATURAL-REQUEST.*file='ps_studios_logo\.bk2'|natural_guest_movie_observed.*file='ps_studios_logo\.bk2'"})
$agcEnqueue=@($err|Where-Object{$_ -match '\[AGC_ASYNC_CP\].*phase=enqueue'})
$agcProcessed=@($err|Where-Object{$_ -match '\[AGC_ASYNC_CP\].*phase=processed'})
$graphics=@($err|Where-Object{$_ -match 'queue=dcb\.graphics.*submission=\d+'})
$scanout=@($err|Where-Object{$_ -match '\[DIRECT_SCANOUT\].*frame_count=\d+'})
$mem=@($err|Where-Object{$_ -match '\[V74\.0\.8\.1\]\[MEM\]'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})
$maxBuilder=Get-MaxLong $builder 'builder_total=(\d+)'
$maxSubmit=Get-MaxLong $submit 'submit_total=(\d+)'
$maxYield=Get-MaxLong $meaning 'yields=(\d+)'
$maxEnqueue=Get-MaxLong $agcEnqueue 'count=(\d+)'
$maxProcessed=Get-MaxLong $agcProcessed 'count=(\d+)'
$maxGraphics=Get-MaxLong $graphics 'queue=dcb\.graphics.*submission=(\d+)'
$maxScanout=Get-MaxLong $scanout 'frame_count=(\d+)'
$active=@($profile|Where-Object{$_ -match 'active=1'})
$stallClass = if($natural.Count -gt 0){'progressed-to-ps-studios'} elseif($maxBuilder -gt 0 -and $maxSubmit -eq 0){'builder-no-driver-submit'} elseif($maxSubmit -gt 0 -and $maxEnqueue -eq 0){'driver-submit-no-async-enqueue'} elseif($maxEnqueue -gt $maxProcessed){'async-consumer-lag'} else {'normal-run-progress-ended-after-drain'}

@(
 'tag=V76.3.21.4-NORMAL-RUN-AGC-PUBLISH-FAIRNESS-DEV-SAFE',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
 "exit_code=$exitCode",
 "fairness_active=$($active.Count -gt 0)",
 "natural_ps_studios_request=$($natural.Count -gt 0)",
 "max_builder_ops=$maxBuilder",
 "max_driver_submits=$maxSubmit",
 "max_fairness_yields=$maxYield",
 "max_agc_enqueue_count=$maxEnqueue",
 "max_agc_processed_count=$maxProcessed",
 "max_draw_submission=$maxGraphics",
 "max_direct_scanout_frame=$maxScanout",
 "stall_class=$stallClass",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '', '--- FAIRNESS PROFILE ---', ($profile|Select-Object -Last 8),
 '', '--- MEANINGFUL PROGRESS LAST ---', ($meaning|Select-Object -Last 96),
 '', '--- NATURAL PS STUDIOS ---', $natural,
 '', '--- ASYNC AGC LAST ---', (($agcEnqueue+$agcProcessed)|Select-Object -Last 64),
 '', '--- LAST MEMORY STATE ---', ($mem|Select-Object -Last 12),
 '', '--- DEVICE LOST ---', $device,
 '', '--- ACCESS VIOLATION ---', $av,
 '', '--- FATAL ---', $fatal
)|Set-Content -LiteralPath $summary -Encoding UTF8
$pack=@($stdout,$stderr,$summary)|Where-Object{Test-Path $_}
Compress-Archive -LiteralPath $pack -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE fairness=$($active.Count -gt 0) natural_ps=$($natural.Count -gt 0) yields=$maxYield stall_class=$stallClass result=$result"
