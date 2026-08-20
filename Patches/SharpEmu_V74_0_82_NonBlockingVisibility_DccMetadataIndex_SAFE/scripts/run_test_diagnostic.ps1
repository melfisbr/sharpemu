param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$ptext=Assert-StructuralContracts
if(-not $ptext.Contains('SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')){throw "$script:Tag V82 marker missing. Run RUN_3 first."}
$exe=Find-SharpEmuExe;if($null -eq $exe){throw "$script:Tag SharpEmu executable not found. Run RUN_3 first."}
$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin';if(-not(Test-Path -LiteralPath $eboot -PathType Leaf)){throw "$script:Tag Demon''s Souls eboot not found: $eboot"}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot "SharpEmu_V74_0_82_NONBLOCKING_DCC_INDEX_$stamp.log"
$summary=Join-Path $script:PatchesRoot "SharpEmu_V74_0_82_NONBLOCKING_DCC_INDEX_SUMMARY_$stamp.txt"
$zip=Join-Path $script:PatchesRoot "SharpEmu_V74_0_82_NONBLOCKING_DCC_INDEX_RESULT_$stamp.zip"
Write-Host ''
Write-Host "$script:Tag TESTE PROFUNDO V82:" -ForegroundColor Cyan
Write-Host '1. Deixe chegar ao mesmo trecho onde o maximo era ~2.2 FPS.'
Write-Host '2. Mantenha por alguns minutos no mesmo trecho de UI.'
Write-Host '3. Feche normalmente.'
Write-Host "$script:Tag RuntimeLog=$log" -ForegroundColor Cyan
Write-Host "$script:Tag Summary=$summary" -ForegroundColor Cyan
Write-Host "$script:Tag ResultZip=$zip" -ForegroundColor Cyan
$oldNB=$env:SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY
$oldBurst=$env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST
$exitCode=-1
try{
  $env:SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY='1'
  $env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST='2'
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$exe;$psi.WorkingDirectory=Split-Path -Parent $exe;$psi.UseShellExecute=$false
  $psi.Arguments=(Quote-ProcessArgument $eboot)+' --log-file '+(Quote-ProcessArgument $log)
  $proc=New-Object System.Diagnostics.Process;$proc.StartInfo=$psi;[void]$proc.Start();$proc.WaitForExit();$exitCode=$proc.ExitCode
}finally{
  if($null -eq $oldNB){Remove-Item Env:SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY -ErrorAction SilentlyContinue}else{$env:SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY=$oldNB}
  if($null -eq $oldBurst){Remove-Item Env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST -ErrorAction SilentlyContinue}else{$env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST=$oldBurst}
}
$out=New-Object System.Collections.Generic.List[string]
$out.Add('[V74.0.82] NonBlocking Visibility + DCC Metadata Index diagnostic')
$out.Add("ExitCode=$exitCode")
$out.Add('nonblocking_ordered_visibility_test=1')
$out.Add('queue_burst_test=2')
if(-not(Test-Path -LiteralPath $log)){
  $out.Add('runtime_log_present=False')
}else{
  $out.Add('runtime_log_present=True')
  $lines=[System.IO.File]::ReadAllLines($log)
  function CountMarker([string]$marker){$n=0;foreach($line in $lines){if($line.Contains($marker)){$n++}};return $n}
  function MaxCounter([string]$marker){$mx=0;foreach($line in $lines){if(-not $line.Contains($marker)){continue};$m=[regex]::Match($line,'count=(\d+)');if($m.Success){$v=[int64]$m.Groups[1].Value;if($v -gt $mx){$mx=$v}}};return $mx}
  function Metric([string]$marker,[string]$token){
    $vals=New-Object System.Collections.Generic.List[double]
    foreach($line in $lines){if(-not $line.Contains($marker)){continue};$m=[regex]::Match($line,[regex]::Escape($token)+'=([0-9]+(?:[.,][0-9]+)?)');if($m.Success){$v=0.0;if([double]::TryParse($m.Groups[1].Value.Replace(',','.'),[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$v)){$vals.Add($v)}}}
    if($vals.Count -eq 0){return 'count=0'}
    $sum=0.0;$max=0.0;foreach($v in $vals){$sum+=$v;if($v -gt $max){$max=$v}}
    return ('count={0} avg_ms={1:F3} max_ms={2:F3}' -f $vals.Count,($sum/$vals.Count),$max)
  }
  $out.Add("first_frame=$(CountMarker 'Vulkan VideoOut presented first frame')")
  $out.Add("device_lost=$(CountMarker 'Vulkan device lost')")
  $out.Add("ordered_fence_wait_max_counter=$(MaxCounter 'vk.ordered_action_fence_wait')")
  $out.Add("ordered_visibility_defer_max_counter=$(MaxCounter '[V74.0.29.3][ORDERED_VISIBILITY_DEFER]')")
  $out.Add("queue_timeline_block_max_counter=$(MaxCounter '[V74.0.42][QUEUE_TIMELINE_BLOCK]')")
  $out.Add("dcc_typed_reject_max_counter=$(MaxCounter '[V74.0.77.1][DCC_TYPED_ALIAS_REJECT]')")
  $out.Add("dcc_index_hit_max_counter=$(MaxCounter '[V74.0.82][DCC_METADATA_INDEX] action=hit')")
  $out.Add("dcc_index_rebuild_max_counter=$(MaxCounter '[V74.0.82][DCC_METADATA_INDEX] action=rebuild')")
  $out.Add("dcc_provenance_recovery_max_counter=$(MaxCounter '[V74.0.80][DCC_PROVENANCE_RECOVERY]')")
  $out.Add("payload_batch_max_counter=$(MaxCounter '[V74.0.56.20][PAYLOAD_BATCH_SUBMIT]')")
  $out.Add("large_snapshot_logged=$(CountMarker 'large_texture_cpu_snapshot')")
  $out.Add("parser_escape_logged=$(CountMarker '[PARSER_ESCAPE]')")
  $out.Add("capacity_yield_max_counter=$(MaxCounter '[V74.0.56.16][CAPACITY_YIELD]')")
  $out.Add("slow_wait_ms: $(Metric '[SLOW_WAIT_PRODUCER]' 'waited_ms')")
  $out.Add("gate_wait_ms: $(Metric '[DEDICATED_WAIT_DRAIN]' 'gate_wait_ms')")
  $out.Add('target_frame_budget_60fps_ms=16.667')
}
$out|Set-Content -LiteralPath $summary -Encoding UTF8
Write-Host '';Get-Content -LiteralPath $summary|ForEach-Object{Write-Host $_}
$items=New-Object System.Collections.Generic.List[string]
if(Test-Path -LiteralPath $log){$items.Add($log)}
if(Test-Path -LiteralPath $summary){$items.Add($summary)}
$recent=Get-ChildItem -LiteralPath $script:PatchesRoot -Filter 'SharpEmu_V74_0_82_APPLY_BUILD_*.log' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -ne $recent){$items.Add($recent.FullName)}
if($items.Count -gt 0){if(Test-Path -LiteralPath $zip){Remove-Item $zip -Force};Compress-Archive -LiteralPath $items.ToArray() -DestinationPath $zip -CompressionLevel Optimal;Write-Host "$script:Tag RESULT ZIP: $zip" -ForegroundColor Green}
