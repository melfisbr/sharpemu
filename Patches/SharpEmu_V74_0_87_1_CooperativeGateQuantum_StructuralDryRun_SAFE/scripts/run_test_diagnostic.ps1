param([Parameter(Mandatory=$true)][string]$PackageRoot,[string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$s=Assert-StructuralContracts
if($s.Checks.V871Field -lt 1 -or $s.Checks.V871Yield -lt 1){
    if($s.Checks.OldV87Field -lt 1 -or $s.Checks.OldV87Yield -lt 1){throw "$script:Tag V87.1/legacy V87 source markers absent. Run RUN_3 first."}
}
$exe=Find-SharpEmuExe
if($null -eq $exe){throw "$script:Tag SharpEmu.exe not found. Run RUN_3 first."}
if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw "$script:Tag eboot missing: $Eboot"}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_87_1_GATE_QUANTUM_${stamp}.log")
$summary=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_87_1_GATE_QUANTUM_SUMMARY_${stamp}.txt")
$zip=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_87_1_GATE_QUANTUM_RESULT_${stamp}.zip")
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($log,'',$utf8)
Write-Host "$script:Tag RuntimeLog=$log"
Write-Host "$script:Tag Summary=$summary"
Write-Host "$script:Tag ResultZip=$zip"
Write-Host "$script:Tag LIVE UTF8 LOG ENABLED (cmd merges native stderr before PowerShell)." -ForegroundColor Green
$cmdLine='"'+$exe+'" "'+$Eboot+'" 2>&1'
$exitCode=-1
try{
    & $env:ComSpec /d /s /c $cmdLine | ForEach-Object {
        $line=[string]$_
        Write-Host $line
        [System.IO.File]::AppendAllText($log,$line+[Environment]::NewLine,$utf8)
    }
    $exitCode=$LASTEXITCODE
}catch{
    [System.IO.File]::AppendAllText($log,($_|Out-String),$utf8)
}
$text=if(Test-Path -LiteralPath $log){[System.IO.File]::ReadAllText($log,$utf8)}else{''}
function MaxCounter([string]$Pattern){$max=0;foreach($m in [regex]::Matches($text,$Pattern)){try{$v=[int64]$m.Groups[1].Value;if($v -gt $max){$max=$v}}catch{}};return $max}
function StatMs([string]$Pattern){$vals=New-Object 'System.Collections.Generic.List[double]';foreach($m in [regex]::Matches($text,$Pattern)){try{$v=[double]::Parse(($m.Groups[1].Value -replace ',','.'),[Globalization.CultureInfo]::InvariantCulture);$vals.Add($v)}catch{}};if($vals.Count -eq 0){return 'count=0'};$arr=$vals.ToArray();[array]::Sort($arr);$sum=0.0;foreach($v in $arr){$sum+=$v};$p50=$arr[[int][Math]::Floor(($arr.Length-1)*0.50)];$p90=$arr[[int][Math]::Floor(($arr.Length-1)*0.90)];return ('count={0} avg={1:F3} p50={2:F3} p90={3:F3} max={4:F3}' -f $arr.Length,($sum/$arr.Length),$p50,$p90,$arr[$arr.Length-1])}
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('[V74.0.87.1] Cooperative Gate Quantum diagnostic')
$out.Add("ExitCode=$exitCode")
$out.Add('runtime_log_present='+[bool](Test-Path -LiteralPath $log))
$out.Add('first_frame='+([regex]::Matches($text,'presented first frame').Count))
$out.Add('device_lost='+([regex]::Matches($text,'(?i)device lost|ErrorDeviceLost').Count))
$out.Add('gate_quantum_yield_max_counter='+(MaxCounter '\[GATE_QUANTUM_YIELD\].*?count=(\d+)'))
$out.Add('gate_owner_wait_drain_max_counter='+(MaxCounter '\[GATE_OWNER_WAIT_DRAIN\].*?count=(\d+)'))
$out.Add('dedicated_wait_drain_max_counter='+(MaxCounter '\[DEDICATED_WAIT_DRAIN\].*?count=(\d+)'))
$out.Add('release_queue_only_max_counter='+(MaxCounter '\[RELEASE_QUEUE_ONLY\].*?count=(\d+)'))
$out.Add('local_texture_payload_dedup_max_counter='+(MaxCounter '\[LOCAL_TEXTURE_PAYLOAD_DEDUP\].*?count=(\d+)'))
$out.Add('cpu_bridge_release_max_counter='+(MaxCounter '\[CPU_BRIDGE_RELEASE\].*?count=(\d+)'))
$out.Add('adaptive_unified_max_counter='+(MaxCounter '\[ADAPTIVE_UNIFIED_COMPUTE\].*?count=(\d+)'))
$out.Add('ordered_visibility_defer_max_counter='+(MaxCounter '\[ORDERED_VISIBILITY_DEFER\].*?count=(\d+)'))
$out.Add('payload_batch_submit_max_counter='+(MaxCounter '\[PAYLOAD_BATCH_SUBMIT\].*?count=(\d+)'))
$out.Add('parser_escape_logged='+([regex]::Matches($text,'\[PARSER_ESCAPE\]').Count))
$out.Add('slow_wait_ms: '+(StatMs 'SLOW_WAIT_PRODUCER.*?waited_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$out.Add('gate_wait_ms: '+(StatMs 'DEDICATED_WAIT_DRAIN.*?gate_wait_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$out.Add('source_defaults: gate_quantum_packets=16 gate_quantum_ms=1; env 0/0 restores legacy')
$out.Add('target_frame_budget_60fps_ms=16.667')
[System.IO.File]::WriteAllLines($summary,$out.ToArray(),$utf8)
$out|ForEach-Object{Write-Host $_}
$items=New-Object 'System.Collections.Generic.List[string]';$items.Add($log);$items.Add($summary)
$build=Get-ChildItem -LiteralPath $script:PatchesRoot -Filter 'SharpEmu_V74_0_87_1_APPLY_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -ne $build){$items.Add($build.FullName)}
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
Compress-Archive -LiteralPath ([string[]]$items.ToArray()) -DestinationPath $zip -Force
Write-Host "$script:Tag RESULT ZIP=$zip" -ForegroundColor Green
