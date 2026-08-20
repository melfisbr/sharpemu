param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
if(-not $s.Agc.Contains('SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')){throw "$script:Tag V85 not applied. Run RUN_3 first."}
$exe=Find-SharpEmuExe;if($null -eq $exe){throw "$script:Tag SharpEmu executable not found. Build first."}
$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin';if(-not(Test-Path -LiteralPath $eboot)){throw "$script:Tag eboot absent: $eboot"}
foreach($n in @('SHARPEMU_KYTY_PM4_BLOCKED_SCHEDULER','SHARPEMU_KYTY_INLINE_WRITE_DATA','SHARPEMU_RELEASE_MEM_QUEUE_COMPLETION_ONLY','SHARPEMU_LOCAL_TEXTURE_PAYLOAD_DEDUP')){Remove-Item -LiteralPath ("Env:"+$n) -ErrorAction SilentlyContinue}
$ts=Get-Date -Format 'yyyyMMdd_HHmmss';$log=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_85_AGGRESSIVE_DRAW_FLOW_${ts}.log");$summary=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_85_AGGRESSIVE_DRAW_FLOW_SUMMARY_${ts}.txt");$zip=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_85_AGGRESSIVE_DRAW_FLOW_RESULT_${ts}.zip")
Write-Host "$script:Tag RuntimeLog=$log";Write-Host "$script:Tag Summary=$summary";Write-Host "$script:Tag ResultZip=$zip"
$psi=New-Object System.Diagnostics.ProcessStartInfo;$psi.FileName=$exe;$psi.Arguments=Quote-ProcessArgument $eboot;$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$false
$p=New-Object System.Diagnostics.Process;$p.StartInfo=$psi
$out=New-Object System.Text.StringBuilder;$err=New-Object System.Text.StringBuilder
$oh=[System.Diagnostics.DataReceivedEventHandler]{param($s,$e)if($null-ne$e.Data){[void]$out.AppendLine($e.Data);Write-Host $e.Data}}
$eh=[System.Diagnostics.DataReceivedEventHandler]{param($s,$e)if($null-ne$e.Data){[void]$err.AppendLine($e.Data);Write-Host $e.Data}}
$p.add_OutputDataReceived($oh);$p.add_ErrorDataReceived($eh);[void]$p.Start();$p.BeginOutputReadLine();$p.BeginErrorReadLine();$p.WaitForExit();$p.WaitForExit();$code=$p.ExitCode
[System.IO.File]::WriteAllText($log,$out.ToString()+$err.ToString(),[System.Text.Encoding]::UTF8)
$t=[System.IO.File]::ReadAllText($log)
function MaxCounter([string]$pattern){$max=0;foreach($m in [regex]::Matches($t,$pattern)){try{$v=[int64]$m.Groups[1].Value;if($v-gt$max){$max=$v}}catch{}};return $max}
function StatMs([string]$pattern){$vals=New-Object System.Collections.Generic.List[double];foreach($m in [regex]::Matches($t,$pattern)){try{$vals.Add([double]::Parse($m.Groups[1].Value.Replace(',','.'),[System.Globalization.CultureInfo]::InvariantCulture))}catch{}};if($vals.Count-eq0){return 'count=0'};$avg=($vals|Measure-Object -Average).Average;$mx=($vals|Measure-Object -Maximum).Maximum;return ('count={0} avg_ms={1:F3} max_ms={2:F3}' -f $vals.Count,$avg,$mx)}
$lines=New-Object System.Collections.Generic.List[string]
$lines.Add('[V74.0.85] Aggressive PM4 + Local Payload Dedup + Release Queue diagnostic');$lines.Add("ExitCode=$code");$lines.Add('runtime_log_present='+[bool](Test-Path -LiteralPath $log));$lines.Add('first_frame='+([regex]::Matches($t,'presented first frame').Count));$lines.Add('device_lost='+([regex]::Matches($t,'(?i)device lost|ErrorDeviceLost').Count));$lines.Add('kyty_pm4_scheduler_max_counter='+(MaxCounter '\[KYTY_PM4_SCHEDULER\].*?count=(\d+)'));$lines.Add('kyty_inline_write_max_counter='+(MaxCounter '\[KYTY_INLINE_WRITE_DATA\].*?count=(\d+)'));$lines.Add('local_texture_payload_dedup_max_counter='+(MaxCounter '\[LOCAL_TEXTURE_PAYLOAD_DEDUP\].*?count=(\d+)'));$lines.Add('release_queue_only_max_counter='+(MaxCounter '\[RELEASE_QUEUE_ONLY\].*?count=(\d+)'));$lines.Add('adaptive_unified_max_counter='+(MaxCounter '\[ADAPTIVE_UNIFIED_COMPUTE\].*?count=(\d+)'));$lines.Add('ordered_visibility_defer_max_counter='+(MaxCounter '\[ORDERED_VISIBILITY_DEFER\].*?count=(\d+)'));$lines.Add('parser_escape_logged='+([regex]::Matches($t,'\[PARSER_ESCAPE\]').Count));$lines.Add('large_snapshot_logged='+([regex]::Matches($t,'large_texture_cpu_snapshot').Count));$lines.Add('array_cache_owner_logged='+([regex]::Matches($t,'\[ARRAY_CACHE_OWNER\]').Count));$lines.Add('slow_wait_ms: '+(StatMs 'SLOW_WAIT_PRODUCER.*?waited_ms=([0-9]+(?:[\.,][0-9]+)?)'));$lines.Add('gate_wait_ms: '+(StatMs 'DEDICATED_WAIT_DRAIN.*?gate_wait_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$alloc=MaxCounter 'alloc2s_mb=(\d+)';$work=MaxCounter 'working_mb=(\d+)';$priv=MaxCounter 'private_mb=(\d+)';$lines.Add("mem_max_alloc2s_mb=$alloc");$lines.Add("mem_max_working_mb=$work");$lines.Add("mem_max_private_mb=$priv");$lines.Add('target_frame_budget_60fps_ms=16.667')
[System.IO.File]::WriteAllLines($summary,$lines,[System.Text.Encoding]::UTF8);$lines|ForEach-Object{Write-Host "$script:Tag $_"}
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force};Compress-Archive -LiteralPath @($log,$summary) -DestinationPath $zip -CompressionLevel Optimal
Write-Host "$script:Tag RESULT ZIP=$zip" -ForegroundColor Green
