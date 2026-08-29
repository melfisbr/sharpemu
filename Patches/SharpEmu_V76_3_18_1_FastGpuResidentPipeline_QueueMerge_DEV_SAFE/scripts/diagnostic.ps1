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
$stdout=Join-Path $Patches ("V76.3.18.1_STDOUT_$stamp.log")
$stderr=Join-Path $Patches ("V76.3.18.1_STDERR_$stamp.log")
$summary=Join-Path $Patches ("V76.3.18.1_SUMMARY_$stamp.txt")
$result=Join-Path $Patches ("V76.3.18.1_RESULT_$stamp.zip")

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
$profile=@($err|Where-Object{$_ -match '\[V76\.3\.18\.1\]\[FAST_GPU_RESIDENT_PROFILE\]'})
$dual=@($err|Where-Object{$_ -match 'DUAL_PHYSICAL_QUEUE|DUAL_QUEUE_SUBMIT|DUAL_QUEUE_PRESENT_JOIN'})
$resident=@($err|Where-Object{$_ -match '\[V74\.0\.118\.0\]\[RESIDENT_SHADER\]'})
$descriptor=@($err|Where-Object{$_ -match '\[V74\.0\.117\.16\]\[DESCRIPTOR_SET_CACHE\]'})
$rebar=@($err|Where-Object{$_ -match '\[V74\.0\.119\.0\]\[REBAR_GLOBAL_DIRECT\]'})
$scalar=@($err|Where-Object{$_ -match '\[V76\.3\.3\]\[RUNTIME_SCALAR_DIRECT\]'})
$payload=@($err|Where-Object{$_ -match 'PAYLOAD_BATCH_SUBMIT'})
$cp=@($err|Where-Object{$_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP\]'})
$perf=@($err|Where-Object{$_ -match '\[PERF\]\[RENDER\]'})
$slow=@($err|Where-Object{$_ -match 'SLOW_WAIT_PRODUCER'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})

@(
'tag=V76.3.18.1-FAST-GPU-RESIDENT-PIPELINE-QUEUE-MERGE',
"runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
"main_loop_detected=$main",
"first_frame_detected=$first",
"profile_lines=$($profile.Count)",
"dual_queue_lines=$($dual.Count)",
"resident_shader_lines=$($resident.Count)",
"descriptor_cache_lines=$($descriptor.Count)",
"rebar_lines=$($rebar.Count)",
"scalar_direct_lines=$($scalar.Count)",
"async_cp_lines=$($cp.Count)",
"slow_wait_lines=$($slow.Count)",
"device_lost_markers=$($device.Count)",
"access_violation_markers=$($av.Count)",
"fatal_markers=$($fatal.Count)",
'',
'--- PROFILE ---',$profile,
'',
'--- BOOT ---',$timeline,
'',
'--- DUAL QUEUE LAST ---',($dual|Select-Object -Last 48),
'',
'--- RESIDENT SHADER LAST ---',($resident|Select-Object -Last 16),
'',
'--- DESCRIPTOR CACHE LAST ---',($descriptor|Select-Object -Last 16),
'',
'--- REBAR LAST ---',($rebar|Select-Object -Last 16),
'',
'--- SCALAR DIRECT LAST ---',($scalar|Select-Object -Last 16),
'',
'--- PAYLOAD LAST ---',($payload|Select-Object -Last 16),
'',
'--- ASYNC CP LAST ---',($cp|Select-Object -Last 16),
'',
'--- SLOW WAIT LAST ---',($slow|Select-Object -Last 16),
'',
'--- PERF LAST ---',($perf|Select-Object -Last 40)
)|Set-Content $summary -Encoding UTF8

Compress-Archive -LiteralPath @($stdout,$stderr,$summary) -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE main=$main first=$first"
Write-Host "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
Write-Host "[$Tag] result=$result"
