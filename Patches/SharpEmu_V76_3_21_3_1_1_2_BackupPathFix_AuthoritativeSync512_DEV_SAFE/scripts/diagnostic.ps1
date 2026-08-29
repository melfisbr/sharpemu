param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Fail "Debug exe ausente: $exe" }
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { Fail "eboot ausente: $game" }
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# No fake progress. Probes are diagnostic-only and do not change guest semantics.
$env:SHARPEMU_BINK_AUTO_BOOT='0'
Remove-Item Env:\SHARPEMU_BINK_BOOT_SEQUENCE -ErrorAction SilentlyContinue
$env:SHARPEMU_TRACE_SCENE_PIPELINE_GAPS='1'
$env:SHARPEMU_TRACE_GEOMETRY_DRAWS='1'
$env:SHARPEMU_TRACE_PRIMITIVE_PIPELINE='1'
$env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS='1'
$env:SHARPEMU_PROFILE_RENDER='1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S='5'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $Patches "V76.3.21.3.1.1.2_STDOUT_$stamp.log"
$stderr=Join-Path $Patches "V76.3.21.3.1.1.2_STDERR_$stamp.log"
$summary=Join-Path $Patches "V76.3.21.3.1.1.2_SUMMARY_$stamp.txt"
$result=Join-Path $Patches "V76.3.21.3.1.1.2_RESULT_$stamp.zip"
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
$authoritative=@($err|Where-Object{$_ -match '\[V76\.3\.21\.3\.1\.1\.2\]\[AUTHORITATIVE_GUEST_PROGRESS\]'})
$closure=@($err|Where-Object{$_ -match 'WEIGHTED_PRODUCER_CLOSURE'})
$sync512=@($closure|Where-Object{$_ -match 'sync_budget=512'})
$sync4096=@($closure|Where-Object{$_ -match 'sync_budget=4096'})
$active512=@($authoritative|Where-Object{$_ -match 'active=1.*closure_sync_budget=512'})
$syncContract=($active512.Count -gt 0 -and $sync512.Count -gt 0 -and $sync4096.Count -eq 0)
$natural=@($err|Where-Object{$_ -match "NATURAL-REQUEST.*file='ps_studios_logo\.bk2'|natural_guest_movie_observed.*file='ps_studios_logo\.bk2'"})
$sceneHull=@($err|Where-Object{$_ -match '\[SCENE_GAP\].*kind=hull-stage-active'})
$sceneDcc=@($err|Where-Object{$_ -match '\[SCENE_GAP\].*kind=nonresident-dcc-decompress'})
$geometry=@($err|Where-Object{$_ -match '\[V25\]\[DRAW\]'})
$threadSnapshots=@($err|Where-Object{$_ -match 'guest_thread\.snapshot'})
$gather=@($out|Where-Object{$_ -match 'ResourcePool::GatherResourceFileInfo\(\) took'})
$agcProcessed=@($err|Where-Object{$_ -match '\[AGC_ASYNC_CP\].*phase=processed'})
$graphics=@($err|Where-Object{$_ -match 'queue=dcb\.graphics.*submission=\d+'})
$scanout=@($err|Where-Object{$_ -match '\[DIRECT_SCANOUT\].*frame_count=\d+'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})
$mem=@($err|Where-Object{$_ -match '^\[MEM\]'})
$maxAgc=Get-MaxLong $agcProcessed 'count=(\d+)'
$maxGraphics=Get-MaxLong $graphics 'queue=dcb\.graphics.*submission=(\d+)'
$maxScanout=Get-MaxLong $scanout 'frame_count=(\d+)'

@(
 'tag=V76.3.21.3.1.1.2-STANDALONE-PRECHECK-FIX-AUTHORITATIVE-SYNC512-DEV-SAFE',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
 "exit_code=$exitCode",
 "authoritative_presenter_active=$($active512.Count -gt 0)",
 "closure_sync512_lines=$($sync512.Count)",
 "closure_sync4096_lines=$($sync4096.Count)",
 "closure_sync_contract_ok=$syncContract",
 "natural_ps_studios_request=$($natural.Count -gt 0)",
 "max_agc_processed_count=$maxAgc",
 "max_draw_submission=$maxGraphics",
 "max_direct_scanout_frame=$maxScanout",
 "scene_gap_hull_stage_active=$($sceneHull.Count)",
 "scene_gap_nonresident_dcc=$($sceneDcc.Count)",
 "geometry_draw_probe_lines=$($geometry.Count)",
 "guest_thread_snapshot_lines=$($threadSnapshots.Count)",
 "gather_resource_file_info_seen=$($gather.Count -gt 0)",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '', '--- AUTHORITATIVE PROFILE ---', ($authoritative|Select-Object -Last 8),
 '', '--- CLOSURE ACTIVATE LAST ---', ($closure|Where-Object{$_ -match 'phase=activate'}|Select-Object -Last 32),
 '', '--- NATURAL PS STUDIOS ---', $natural,
 '', '--- SCENE PIPELINE GAPS ---', (($sceneHull+$sceneDcc)|Select-Object -Last 64),
 '', '--- GEOMETRY DRAW PROBE LAST ---', ($geometry|Select-Object -Last 64),
 '', '--- GUEST THREAD SNAPSHOTS LAST ---', ($threadSnapshots|Select-Object -Last 64),
 '', '--- GATHER RESOURCE INFO ---', $gather,
 '', '--- LAST MEMORY STATE ---', ($mem|Select-Object -Last 8),
 '', '--- DEVICE LOST ---', $device,
 '', '--- ACCESS VIOLATION ---', $av,
 '', '--- FATAL ---', $fatal
)|Set-Content -LiteralPath $summary -Encoding UTF8
$pack=@($stdout,$stderr,$summary)|Where-Object{Test-Path $_}
Compress-Archive -LiteralPath $pack -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE sync_contract=$syncContract natural_ps=$($natural.Count -gt 0) hull_gap=$($sceneHull.Count) result=$result"
