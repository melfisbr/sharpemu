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
$stdout = Join-Path $Patches ("V76.3.20_0_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.20_0_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.20_0_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.20_0_RESULT_$stamp.zip")

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

$resid=@($err|Where-Object{$_ -match '\[V74\.0\.117\.13\]\[SHADER_GLOBAL_RESIDENCY\]'})
$upload=@($err|Where-Object{$_ -match '\[V74\.0\.117\.12\]\[SHADER_GLOBAL_DIRECT_UPLOAD\]'})
$frontend=@($err|Where-Object{$_ -match '\[V74\.0\.117\.10\]\[SHADER_FRONTEND_RESOURCE_FASTPATH\]'})
$lastResid=$resid|Select-Object -Last 1
$lastUpload=$upload|Select-Object -Last 1
@(
 'tag=V76.3.20.0-GLOBAL-RESIDENCY-CAPACITY',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
 "main_loop_detected=$main",
 "first_frame_detected=$first",
 "residency_trace_lines=$($resid.Count)",
 "direct_upload_trace_lines=$($upload.Count)",
 "frontend_trace_lines=$($frontend.Count)",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '',
 '--- BOOT ---',$timeline,
 '',
 '--- RESIDENCY LAST ---',$lastResid,
 '',
 '--- DIRECT UPLOAD LAST ---',$lastUpload,
 '',
 '--- FRONTEND LAST ---',($frontend|Select-Object -Last 16),
 '',
 '--- PERF LAST ---',($perf|Select-Object -Last 32)
)|Set-Content $summary -Encoding UTF8

Compress-Archive -LiteralPath @($stdout,$stderr,$summary) -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE main=$main first=$first device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
Write-Host "[$Tag] result=$result"
