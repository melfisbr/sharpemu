param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Fail "EXE ausente: $exe" }
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { Fail "eboot ausente: $game" }

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$env:SHARPEMU_PROFILE_RENDER='1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S='5'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.20_1_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.20_1_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.20_1_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.20_1_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main=$false
$first=$false
$deadline=$start.AddSeconds(220)
while(-not $p.HasExited -and (Get-Date)-lt $deadline) {
    Start-Sleep -Milliseconds 500
    if(Test-Path $stdout) {
        $main=Select-String -LiteralPath $stdout -Pattern 'Starting main loop:' -Quiet -ErrorAction SilentlyContinue
    }
    if(Test-Path $stderr) {
        $first=Select-String -LiteralPath $stderr -Pattern 'Vulkan VideoOut presented first frame' -Quiet -ErrorAction SilentlyContinue
    }
    if($main -and $first -and (Get-Date)-gt $start.AddSeconds(190)) { break }
}
if(-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

$out=if(Test-Path $stdout){@(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)}else{@()}
$err=if(Test-Path $stderr){@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)}else{@()}

$timeline=@($out|Where-Object{$_ -match 'Starting Initialization:|RecordResourceDependencies\(\) took|Finished Initialization:|Starting Script:|Starting main loop:|GatherResourceFileInfo\(\) took'})
$perf=@($err|Where-Object{$_ -match '\[PERF\]\[RENDER\]'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})

$fast=@($err|Where-Object{$_ -match '\[V74\.0\.94\.3\]\[WAIT_REGISTRY_FAST_ONLY\]'})
$drain=@($err|Where-Object{$_ -match '\[V74\.0\.71\]\[DEDICATED_WAIT_DRAIN\]'})
$throttle=@($err|Where-Object{$_ -match '\[V76\.3\.8\.4\]\[WAIT_FULL_SCAN_THROTTLE\]'})
$slow=@($err|Where-Object{$_ -match 'SLOW_WAIT_PRODUCER'})
$maxFull=0L
foreach($line in $fast){
 $m=[regex]::Match($line,'full_collects=(\d+)')
 if($m.Success){$v=[long]$m.Groups[1].Value;if($v-gt$maxFull){$maxFull=$v}}
}
@(
 'tag=V76.3.20.1-EVENT-FIRST-WAIT-WATCHDOG',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
 "main_loop_detected=$main",
 "first_frame_detected=$first",
 "wait_full_collects_max=$maxFull",
 "fast_only_trace_lines=$($fast.Count)",
 "dedicated_drain_trace_lines=$($drain.Count)",
 "fullscan_throttle_trace_lines=$($throttle.Count)",
 "slow_wait_lines=$($slow.Count)",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '',
 '--- BOOT ---',$timeline,
 '',
 '--- WAIT FAST LAST ---',($fast|Select-Object -Last 32),
 '',
 '--- WAIT DRAIN LAST ---',($drain|Select-Object -Last 32),
 '',
 '--- THROTTLE LAST ---',($throttle|Select-Object -Last 32),
 '',
 '--- SLOW WAIT LAST ---',($slow|Select-Object -Last 24),
 '',
 '--- PERF LAST ---',($perf|Select-Object -Last 32)
)|Set-Content $summary -Encoding UTF8

Compress-Archive -LiteralPath @($stdout,$stderr,$summary) -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE main=$main first=$first device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
Write-Host "[$Tag] result=$result"
