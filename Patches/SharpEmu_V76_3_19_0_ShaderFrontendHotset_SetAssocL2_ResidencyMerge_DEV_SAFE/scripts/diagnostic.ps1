param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe=Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game='F:\JOGOSPS5\PPSA01341\eboot.bin'
if(-not(Test-Path $exe)){Fail "EXE ausente: $exe"}
if(-not(Test-Path $game)){Fail "eboot ausente: $game"}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$env:SHARPEMU_PROFILE_RENDER='1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S='5'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $Patches ("V76.3.19.0_STDOUT_$stamp.log")
$stderr=Join-Path $Patches ("V76.3.19.0_STDERR_$stamp.log")
$summary=Join-Path $Patches ("V76.3.19.0_SUMMARY_$stamp.txt")
$result=Join-Path $Patches ("V76.3.19.0_RESULT_$stamp.zip")

$start=Get-Date
$p=Start-Process $exe -ArgumentList @($game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$main=$false;$first=$false
$deadline=$start.AddSeconds(220)
while(-not$p.HasExited -and (Get-Date)-lt$deadline){
 Start-Sleep -Milliseconds 500
 if(Test-Path $stdout){$main=Select-String $stdout -Pattern 'Starting main loop:' -Quiet -ErrorAction SilentlyContinue}
 if(Test-Path $stderr){$first=Select-String $stderr -Pattern 'Vulkan VideoOut presented first frame' -Quiet -ErrorAction SilentlyContinue}
 if($main -and $first -and (Get-Date)-gt$start.AddSeconds(190)){break}
}
if(-not$p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;$p.WaitForExit()}

$out=if(Test-Path $stdout){@(Get-Content $stdout)}else{@()}
$err=if(Test-Path $stderr){@(Get-Content $stderr)}else{@()}

$timeline=@($out|Where-Object{$_ -match 'Starting Initialization:|RecordResourceDependencies\(\) took|Finished Initialization:|Starting Script:|Starting main loop:|GatherResourceFileInfo\(\) took'})
$profile=@($err|Where-Object{$_ -match '\[V76\.3\.19\.0\]\[SHADER_FRONTEND_HOTSET_PROFILE\]'})
$front=@($err|Where-Object{$_ -match 'SHADER_FRONTEND_RESOURCE_FASTPATH'})
$resid=@($err|Where-Object{$_ -match 'SHADER_GLOBAL_RESIDENCY'})
$direct=@($err|Where-Object{$_ -match 'SHADER_GLOBAL_DIRECT_UPLOAD'})
$rshader=@($err|Where-Object{$_ -match '\[V74\.0\.118\.0\]\[RESIDENT_SHADER\]'})
$dset=@($err|Where-Object{$_ -match '\[V74\.0\.117\.16\]\[DESCRIPTOR_SET_CACHE\]'})
$dual=@($err|Where-Object{$_ -match '\[V74\.0\.113\.1\]\[DUAL_PHYSICAL_QUEUE\]|\[V74\.0\.113\.1\]\[DUAL_QUEUE_SUBMIT\]'})
$payload=@($err|Where-Object{$_ -match 'PAYLOAD_BATCH_SUBMIT'})
$perf=@($err|Where-Object{$_ -match '\[PERF\]\[RENDER\]'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})

@(
 'tag=V76.3.19.0-SHADER-FRONTEND-HOTSET',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
 "main_loop_detected=$main",
 "first_frame_detected=$first",
 "frontend_trace_lines=$($front.Count)",
 "residency_trace_lines=$($resid.Count)",
 "direct_upload_trace_lines=$($direct.Count)",
 "resident_shader_trace_lines=$($rshader.Count)",
 "descriptor_cache_trace_lines=$($dset.Count)",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '',
 '--- PROFILE ---',$profile,
 '',
 '--- BOOT ---',$timeline,
 '',
 '--- FRONTEND LAST ---',($front|Select-Object -Last 16),
 '',
 '--- GLOBAL RESIDENCY LAST ---',($resid|Select-Object -Last 16),
 '',
 '--- DIRECT GLOBAL UPLOAD LAST ---',($direct|Select-Object -Last 16),
 '',
 '--- RESIDENT SHADER LAST ---',($rshader|Select-Object -Last 12),
 '',
 '--- DESCRIPTOR CACHE LAST ---',($dset|Select-Object -Last 12),
 '',
 '--- DUAL QUEUE LAST ---',($dual|Select-Object -Last 24),
 '',
 '--- PAYLOAD LAST ---',($payload|Select-Object -Last 16),
 '',
 '--- PERF LAST ---',($perf|Select-Object -Last 32)
)|Set-Content $summary -Encoding UTF8

Compress-Archive -LiteralPath @($stdout,$stderr,$summary) -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE main=$main first=$first frontend=$($front.Count) residency=$($resid.Count)"
Write-Host "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
Write-Host "[$Tag] result=$result"
