param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$ptext=Assert-StructuralContracts
if(-not $ptext.Contains('SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')){throw "$script:Tag semantic boundary repair marker missing. Run RUN_3 first."}
$exe=Find-SharpEmuExe;if($null -eq $exe){throw "$script:Tag SharpEmu executable not found. Run RUN_3 first."}
$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin';if(-not(Test-Path -LiteralPath $eboot -PathType Leaf)){throw "$script:Tag Demon''s Souls eboot not found: $eboot"}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot "SharpEmu_V74_0_81_2_SEMANTIC_STABILITY_DRAW_FLOW_$stamp.log"
$summary=Join-Path $script:PatchesRoot "SharpEmu_V74_0_81_2_SEMANTIC_STABILITY_DRAW_FLOW_SUMMARY_$stamp.txt"
$zip=Join-Path $script:PatchesRoot "SharpEmu_V74_0_81_2_SEMANTIC_STABILITY_DRAW_FLOW_RESULT_$stamp.zip"
Write-Host ''
Write-Host "$script:Tag TESTE STABILITY + DRAW FLOW:" -ForegroundColor Cyan
Write-Host '1. Confirme que o jogo passa do primeiro frame sem Vulkan DeviceLost.'
Write-Host '2. Deixe chegar ao mesmo trecho de UI/2 FPS usado no teste anterior.'
Write-Host '3. Feche o SharpEmu depois de uma janela representativa.'
Write-Host "$script:Tag RuntimeLog=$log" -ForegroundColor Cyan
Write-Host "$script:Tag Summary=$summary" -ForegroundColor Cyan
Write-Host "$script:Tag ResultZip=$zip" -ForegroundColor Cyan
Write-Host ''

$oldBurst=$env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST
$exitCode=-1
try{
    $env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST='2'
    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$exe
    $psi.WorkingDirectory=Split-Path -Parent $exe
    $psi.UseShellExecute=$false
    $psi.Arguments=(Quote-ProcessArgument $eboot)+' --log-file '+(Quote-ProcessArgument $log)
    $proc=New-Object System.Diagnostics.Process
    $proc.StartInfo=$psi
    [void]$proc.Start()
    $proc.WaitForExit()
    $exitCode=$proc.ExitCode
}finally{
    if($null -eq $oldBurst){Remove-Item Env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST -ErrorAction SilentlyContinue}else{$env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST=$oldBurst}
}

$out=New-Object System.Collections.Generic.List[string]
$out.Add('[V74.0.81.2] Semantic Boundary Repair diagnostic')
$out.Add("ExitCode=$exitCode")
$out.Add('queue_burst_test_value=2')

if(-not(Test-Path -LiteralPath $log)){
    $out.Add('runtime_log_present=False')
    $out.Add('ERROR=no_runtime_log_produced')
}else{
    $out.Add('runtime_log_present=True')
    try{
        $lines=[System.IO.File]::ReadAllLines($log)
        function CountMarker([string]$marker){$n=0;foreach($line in $lines){if($line.Contains($marker)){$n++}};return $n}
        function Metric([string]$marker,[string]$token){
            $vals=New-Object System.Collections.Generic.List[double]
            foreach($line in $lines){if(-not $line.Contains($marker)){continue};$m=[regex]::Match($line,[regex]::Escape($token)+'=([0-9]+(?:[.,][0-9]+)?)');if($m.Success){$v=0.0;if([double]::TryParse($m.Groups[1].Value.Replace(',','.'),[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$v)){$vals.Add($v)}}}
            if($vals.Count -eq 0){return 'count=0'}
            $sum=0.0;$max=0.0;foreach($v in $vals){$sum+=$v;if($v -gt $max){$max=$v}}
            return ('count={0} avg_ms={1:F3} max_ms={2:F3}' -f $vals.Count,($sum/$vals.Count),$max)
        }
        function LastLine([string]$marker){$last=$null;foreach($line in $lines){if($line.Contains($marker)){$last=$line}};return $last}
        $batchLast=LastLine '[V74.0.56.20][PAYLOAD_BATCH_SUBMIT]'
        $batch='none'
        if($null -ne $batchLast){$m=[regex]::Match($batchLast,'count=(\d+).*work=(\d+).*total_work=(\d+).*avg=([0-9.,]+)');if($m.Success){$batch=('count={0} last_work={1} total_work={2} avg_work_per_submit={3}' -f $m.Groups[1].Value,$m.Groups[2].Value,$m.Groups[3].Value,$m.Groups[4].Value)}}
        $out.Add("payload_batch=$batch")
        $out.Add("first_frame_logged=$(CountMarker 'Vulkan VideoOut presented first frame')")
        $out.Add("device_lost_logged=$(CountMarker 'Vulkan device lost')")
        $out.Add("error_device_lost_logged=$(CountMarker 'ErrorDeviceLost')")
        $out.Add("ordered_action_fence_wait_logged=$(CountMarker 'vk.ordered_action_fence_wait')")
        $out.Add("queue_submission_burst_logged=$(CountMarker '[V74.0.43][QUEUE_SUBMISSION_BURST]')")
        $out.Add("queue_to_inflight_logged=$(CountMarker '[V74.0.81][QUEUE_TO_INFLIGHT]')")
        $out.Add("parser_escape_logged=$(CountMarker '[PARSER_ESCAPE]')")
        $out.Add("slow_wait_ms: $(Metric '[SLOW_WAIT_PRODUCER]' 'waited_ms')")
        $out.Add("gate_wait_ms: $(Metric '[DEDICATED_WAIT_DRAIN]' 'gate_wait_ms')")
        $out.Add("backpressure_ms: $(Metric '[BACKPRESSURE_WAIT]' 'ms')")
        $out.Add('target_frame_budget_60fps_ms=16.667')
    }catch{
        $out.Add('diagnostic_parser_error='+$_.Exception.Message)
    }
}
$out|Set-Content -LiteralPath $summary -Encoding UTF8
Write-Host ''
Get-Content -LiteralPath $summary|ForEach-Object{Write-Host $_}

$items=New-Object System.Collections.Generic.List[string]
if(Test-Path -LiteralPath $log){$items.Add($log)}
if(Test-Path -LiteralPath $summary){$items.Add($summary)}
$recent=Get-ChildItem -LiteralPath $script:PatchesRoot -Filter 'SharpEmu_V74_0_81_2_APPLY_BUILD_*.log' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -ne $recent){$items.Add($recent.FullName)}
if($items.Count -gt 0){
    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -LiteralPath $items.ToArray() -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "$script:Tag RESULT ZIP: $zip" -ForegroundColor Green
}
