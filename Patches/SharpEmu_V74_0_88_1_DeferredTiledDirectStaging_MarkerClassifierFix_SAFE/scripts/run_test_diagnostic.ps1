param([Parameter(Mandatory=$true)][string]$PackageRoot,[string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$dry=Invoke-CheckoutDryRun $false
if($dry.State -ne 'Applied'){throw "$script:Tag V88 source markers absent. Run RUN_3 first."}
$exe=Find-SharpEmuExe
if($null -eq $exe){throw "$script:Tag SharpEmu.exe not found. Run RUN_3 first."}
if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw "$script:Tag eboot missing: $Eboot"}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_88_1_DIRECT_STAGING_${stamp}.log")
$summary=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_88_1_DIRECT_STAGING_SUMMARY_${stamp}.txt")
$zip=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_88_1_DIRECT_STAGING_RESULT_${stamp}.zip")
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($log,'',$utf8)
Write-Host "$script:Tag RuntimeLog=$log"
Write-Host "$script:Tag Summary=$summary"
Write-Host "$script:Tag ResultZip=$zip"
Write-Host "$script:Tag LIVE UTF8 LOG ENABLED." -ForegroundColor Green
$cmdLine='"'+$exe+'" "'+$Eboot+'" 2>&1'
$exitCode=-1
try{
    & $env:ComSpec /d /s /c $cmdLine | ForEach-Object {$line=[string]$_;Write-Host $line;[System.IO.File]::AppendAllText($log,$line+[Environment]::NewLine,$utf8)}
    $exitCode=$LASTEXITCODE
}catch{[System.IO.File]::AppendAllText($log,($_|Out-String),$utf8)}
$text=if(Test-Path -LiteralPath $log){[System.IO.File]::ReadAllText($log,$utf8)}else{''}
function MaxCounter([string]$Pattern){$max=0;foreach($m in [regex]::Matches($text,$Pattern)){try{$v=[int64]$m.Groups[1].Value;if($v -gt $max){$max=$v}}catch{}};return $max}
function SumBytes([string]$Pattern){$sum=[int64]0;foreach($m in [regex]::Matches($text,$Pattern)){try{$sum+=[int64]$m.Groups[1].Value}catch{}};return $sum}
function StatMs([string]$Pattern,[double]$MaxAllowed=1.0e20){$vals=New-Object 'System.Collections.Generic.List[double]';foreach($m in [regex]::Matches($text,$Pattern)){try{$v=[double]::Parse(($m.Groups[1].Value -replace ',','.'),[Globalization.CultureInfo]::InvariantCulture);if($v -le $MaxAllowed){$vals.Add($v)}}catch{}};if($vals.Count -eq 0){return 'count=0'};$arr=$vals.ToArray();[array]::Sort($arr);$sum=0.0;foreach($v in $arr){$sum+=$v};$p50=$arr[[int][Math]::Floor(($arr.Length-1)*0.50)];$p90=$arr[[int][Math]::Floor(($arr.Length-1)*0.90)];return ('count={0} avg={1:F3} p50={2:F3} p90={3:F3} max={4:F3}' -f $arr.Length,($sum/$arr.Length),$p50,$p90,$arr[$arr.Length-1])}
function MaxMem([string]$Name){$max=0;foreach($m in [regex]::Matches($text,[regex]::Escape($Name)+'=(\d+)')){try{$v=[int64]$m.Groups[1].Value;if($v -gt $max){$max=$v}}catch{}};return $max}
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('[V74.0.88.1] Deferred Tiled Direct Staging diagnostic')
$out.Add("ExitCode=$exitCode")
$out.Add('runtime_log_present='+[bool](Test-Path -LiteralPath $log))
$out.Add('first_frame='+([regex]::Matches($text,'presented first frame').Count))
$out.Add('device_lost='+([regex]::Matches($text,'(?i)device lost|ErrorDeviceLost').Count))
$out.Add('deferred_tiled_array_max_counter='+(MaxCounter '\[DEFERRED_TILED_ARRAY\].*?count=(\d+)'))
$out.Add('deferred_tiled_single_max_counter='+(MaxCounter '\[DEFERRED_TILED_SINGLE\].*?count=(\d+)'))
$out.Add('direct_guest_staging_max_counter='+(MaxCounter '\[DIRECT_GUEST_STAGING\].*?count=(\d+)'))
$out.Add('direct_guest_staging_fallback_max_counter='+(MaxCounter '\[DIRECT_GUEST_STAGING_FALLBACK\].*?count=(\d+)'))
$out.Add('direct_guest_staging_total_mb='+[Math]::Round((SumBytes '\[DIRECT_GUEST_STAGING\].*?bytes=(\d+)')/1MB,2))
$out.Add('legacy_array_cache_owner_logged='+([regex]::Matches($text,'\[ARRAY_CACHE_OWNER\]').Count))
$out.Add('legacy_large_texture_snapshot_logged='+([regex]::Matches($text,'large_texture_cpu_snapshot').Count))
$out.Add('gate_quantum_yield_max_counter='+(MaxCounter '\[GATE_QUANTUM_YIELD\].*?count=(\d+)'))
$out.Add('gate_quantum_elapsed_us_all: '+(StatMs 'GATE_QUANTUM_YIELD.*?elapsed_us=([0-9]+(?:[\.,][0-9]+)?)'))
$out.Add('gate_wait_ms_all: '+(StatMs 'DEDICATED_WAIT_DRAIN.*?gate_wait_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$out.Add('gate_wait_ms_steady_le4000: '+(StatMs 'DEDICATED_WAIT_DRAIN.*?gate_wait_ms=([0-9]+(?:[\.,][0-9]+)?)' 4000.0))
$out.Add('slow_wait_ms_all: '+(StatMs 'SLOW_WAIT_PRODUCER.*?waited_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$out.Add('slow_wait_ms_steady_le4000: '+(StatMs 'SLOW_WAIT_PRODUCER.*?waited_ms=([0-9]+(?:[\.,][0-9]+)?)' 4000.0))
$out.Add('payload_batch_submit_max_counter='+(MaxCounter '\[PAYLOAD_BATCH_SUBMIT\].*?count=(\d+)'))
$out.Add('mem_max_alloc2s_mb='+(MaxMem 'alloc2s_mb'))
$out.Add('mem_max_working_mb='+(MaxMem 'working_mb'))
$out.Add('mem_max_private_mb='+(MaxMem 'private_mb'))
$out.Add('source_defaults: defer_large_tiled=on threshold_mb=8; SHARPEMU_DEFER_LARGE_TILED_GUEST_READ=0 restores legacy')
$out.Add('target_frame_budget_60fps_ms=16.667')
[System.IO.File]::WriteAllLines($summary,$out.ToArray(),$utf8)
$out|ForEach-Object{Write-Host $_}
$items=New-Object 'System.Collections.Generic.List[string]';$items.Add($log);$items.Add($summary)
$build=Get-ChildItem -LiteralPath $script:PatchesRoot -Filter 'SharpEmu_V74_0_88_1_APPLY_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -ne $build){$items.Add($build.FullName)}
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
Compress-Archive -LiteralPath ([string[]]$items.ToArray()) -DestinationPath $zip -Force
Write-Host "$script:Tag RESULT ZIP=$zip" -ForegroundColor Green
