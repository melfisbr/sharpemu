param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$ptext=Assert-StructuralContracts
foreach($m in @('SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW','SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR','SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT')){if(-not $ptext.Contains($m)){throw "$script:Tag source patch marker missing: $m. Run RUN_3 first."}}
$exe=Find-SharpEmuExe;if($null -eq $exe){throw "$script:Tag SharpEmu executable not found. Run RUN_3 first."}
$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin';if(-not(Test-Path -LiteralPath $eboot -PathType Leaf)){throw "$script:Tag Demon''s Souls eboot not found: $eboot"}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot "SharpEmu_V74_0_81_DEEP_DRAW_FLOW_$stamp.log"
$summary=Join-Path $script:PatchesRoot "SharpEmu_V74_0_81_DEEP_DRAW_FLOW_SUMMARY_$stamp.txt"
$zip=Join-Path $script:PatchesRoot "SharpEmu_V74_0_81_DEEP_DRAW_FLOW_RESULT_$stamp.zip"
Write-Host ''
Write-Host "$script:Tag TESTE PROFUNDO DE DESEMPENHO:" -ForegroundColor Cyan
Write-Host '1. Execute normalmente ate a UI/trecho onde voce via no maximo ~2 FPS.'
Write-Host '2. Deixe rodar por pelo menos uma janela representativa de draws/compute.'
Write-Host '3. Feche o SharpEmu depois de observar o FPS maximo/estavel.'
Write-Host ''
$psi=New-Object System.Diagnostics.ProcessStartInfo;$psi.FileName=$exe;$psi.WorkingDirectory=Split-Path -Parent $exe;$psi.UseShellExecute=$false
$psi.Arguments=(Quote-ProcessArgument $eboot)+' --log-file '+(Quote-ProcessArgument $log)
$proc=New-Object System.Diagnostics.Process;$proc.StartInfo=$psi;[void]$proc.Start();$proc.WaitForExit()
if(-not(Test-Path -LiteralPath $log)){"No log file produced. ExitCode=$($proc.ExitCode)"|Set-Content -LiteralPath $summary -Encoding UTF8}else{
 $lines=[System.IO.File]::ReadAllLines($log)
 function Metric([string]$marker,[string]$token){$vals=New-Object System.Collections.Generic.List[double];foreach($line in $lines){if(-not $line.Contains($marker)){continue};$m=[regex]::Match($line,[regex]::Escape($token)+'=([0-9]+(?:[.,][0-9]+)?)');if($m.Success){$v=0.0;if([double]::TryParse($m.Groups[1].Value.Replace(',','.'),[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$v)){$vals.Add($v)}}};if($vals.Count -eq 0){return 'count=0'};$sum=0.0;$max=0.0;foreach($v in $vals){$sum+=$v;if($v -gt $max){$max=$v}};return ('count={0} avg_ms={1:F3} max_ms={2:F3}' -f $vals.Count,($sum/$vals.Count),$max)}
 function LastLine([string]$marker){$last=$null;foreach($line in $lines){if($line.Contains($marker)){$last=$line}};return $last}
 function MaxCounter([string]$marker){$max=0;foreach($line in $lines){if(-not $line.Contains($marker)){continue};$m=[regex]::Match($line,'count=(\d+)');if($m.Success){$v=[int64]$m.Groups[1].Value;if($v -gt $max){$max=$v}}};return $max}
 $batchLast=LastLine '[V74.0.56.20][PAYLOAD_BATCH_SUBMIT]'
 $batchAvg='none';if($batchLast){$m=[regex]::Match($batchLast,'count=(\d+).*work=(\d+).*total_work=(\d+).*avg=([0-9.,]+)');if($m.Success){$batchAvg=('count={0} last_work={1} total_work={2} avg_work_per_submit={3}' -f $m.Groups[1].Value,$m.Groups[2].Value,$m.Groups[3].Value,$m.Groups[4].Value)}}
 $out=@()
 $out+='[V74.0.81] Deep Draw Submission Flow diagnostic'
 $out+="ExitCode=$($proc.ExitCode)"
 $out+="payload_batch=$batchAvg"
 $out+="queue_submission_burst_logged=$(($lines|Select-String -SimpleMatch '[V74.0.43][QUEUE_SUBMISSION_BURST]').Count)"
 $out+="queue_to_inflight_logged=$(($lines|Select-String -SimpleMatch '[V74.0.81][QUEUE_TO_INFLIGHT]').Count)"
 $out+="parser_escape_logged=$(($lines|Select-String -SimpleMatch '[PARSER_ESCAPE]').Count)"
 $out+="capacity_yield_max_counter=$(MaxCounter '[CAPACITY_YIELD]')"
 $out+="dcc_typed_reject_max_counter=$(MaxCounter '[DCC_TYPED_ALIAS_REJECT]')"
 $out+="dcc_provenance_recovery_logged=$(($lines|Select-String -SimpleMatch '[V74.0.80][DCC_PROVENANCE_RECOVERY]').Count)"
 $out+="slow_wait_ms: $(Metric '[SLOW_WAIT_PRODUCER]' 'waited_ms')"
 $out+="gate_wait_ms: $(Metric '[DEDICATED_WAIT_DRAIN]' 'gate_wait_ms')"
 $out+="backpressure_ms: $(Metric '[BACKPRESSURE_WAIT]' 'ms')"
 $out+="target_frame_budget_60fps_ms=16.667"
 $out|Set-Content -LiteralPath $summary -Encoding UTF8
 Write-Host '';Get-Content -LiteralPath $summary|ForEach-Object{Write-Host $_}
}
$items=@();if(Test-Path -LiteralPath $log){$items+=$log};if(Test-Path -LiteralPath $summary){$items+=$summary}
$recent=Get-ChildItem -LiteralPath $script:PatchesRoot -Filter 'SharpEmu_V74_0_81_APPLY_BUILD_*.log' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($recent){$items+=$recent.FullName}
if($items.Count -ne 0){if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force};Compress-Archive -LiteralPath $items -DestinationPath $zip -CompressionLevel Optimal;Write-Host "$script:Tag RESULT ZIP: $zip" -ForegroundColor Green}
