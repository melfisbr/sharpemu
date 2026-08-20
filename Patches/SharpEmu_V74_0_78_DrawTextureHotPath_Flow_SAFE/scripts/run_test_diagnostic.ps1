param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$null=Assert-StructuralContracts

$exe=Find-SharpEmuExe
if($null -eq $exe){throw "$script:Tag SharpEmu executable not found. Run RUN_3 first."}
$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
if(-not(Test-Path -LiteralPath $eboot -PathType Leaf)){throw "$script:Tag Demon''s Souls eboot not found: $eboot"}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot "SharpEmu_V74_0_78_DRAW_HOTPATH_$stamp.log"
$summary=Join-Path $script:PatchesRoot "SharpEmu_V74_0_78_DRAW_HOTPATH_SUMMARY_$stamp.txt"
$zip=Join-Path $script:PatchesRoot "SharpEmu_V74_0_78_DRAW_HOTPATH_RESULT_$stamp.zip"

Write-Host ''
Write-Host "$script:Tag TESTE DE DESEMPENHO:" -ForegroundColor Cyan
Write-Host '1. Deixe o Demon''s Souls executar normalmente por alguns minutos.'
Write-Host '2. Nao use fast-boot; queremos medir draws/compute reais.'
Write-Host '3. Depois de observar a lentidao ou uma melhora clara, feche o SharpEmu.'
Write-Host ''

$psi=New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName=$exe
$psi.WorkingDirectory=Split-Path -Parent $exe
$psi.UseShellExecute=$false
# PowerShell 5.1 compatible launcher: use the single Arguments string.
$psi.Arguments=(Quote-ProcessArgument $eboot)+' --log-file '+(Quote-ProcessArgument $log)
$p=New-Object System.Diagnostics.Process
$p.StartInfo=$psi
[void]$p.Start()
$p.WaitForExit()

if(-not(Test-Path -LiteralPath $log)){
    "No log file was produced at $log`r`nExitCode=$($p.ExitCode)" | Set-Content -LiteralPath $summary -Encoding UTF8
}else{
    $lines=[System.IO.File]::ReadAllLines($log)
    function Parse-FilteredMetric([string]$marker,[string]$token){
        $values=New-Object System.Collections.Generic.List[double]
        foreach($line in $lines){
            if(-not $line.Contains($marker)){continue}
            $m=[regex]::Match($line, [regex]::Escape($token)+'=([0-9]+(?:[.,][0-9]+)?)')
            if($m.Success){
                $v=0.0
                if([double]::TryParse($m.Groups[1].Value.Replace(',','.'),[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$v)){
                    $values.Add($v)
                }
            }
        }
        if($values.Count -eq 0){return 'count=0'}
        $sum=0.0;$max=0.0
        foreach($v in $values){$sum+=$v;if($v -gt $max){$max=$v}}
        return ('count={0} avg_ms={1:F3} max_ms={2:F3}' -f $values.Count,($sum/$values.Count),$max)
    }

    $alias78=($lines | Select-String -SimpleMatch '[V74.0.78][PRE_SNAPSHOT_SAMPLER_ALIAS]').Count
    $alias73=($lines | Select-String -SimpleMatch '[V74.0.73][SAMPLER_IMAGE_ALIAS]').Count
    $source0=($lines | Select-String -Pattern '\[V74\.0\.73\]\[SAMPLER_IMAGE_ALIAS\].*source_kb=0(?:\s|$)').Count

    $out=@()
    $out+="[V74.0.78] Draw Texture Hot Path diagnostic"
    $out+="ExitCode=$($p.ExitCode)"
    $out+="pre_snapshot_alias_hits_logged=$alias78"
    $out+="sampler_alias_lines=$alias73"
    $out+="sampler_alias_source_kb_0=$source0"
    $out+="draw_texture_ms: $(Parse-FilteredMetric '[DRAW_RESOURCE_PHASES]' 'texture_ms')"
    $out+="compute_texture_ms: $(Parse-FilteredMetric '[COMPUTE_RESOURCE_PHASES]' 'texture_ms')"
    $out+="slow_wait_ms: $(Parse-FilteredMetric '[SLOW_WAIT_PRODUCER]' 'waited_ms')"
    $out+="gate_wait_ms: $(Parse-FilteredMetric '[DEDICATED_WAIT_DRAIN]' 'gate_wait_ms')"
    $out+="backpressure_ms: $(Parse-FilteredMetric '[BACKPRESSURE_WAIT]' 'ms')"
    $out+="target_frame_budget_60fps_ms=16.667"
    $out | Set-Content -LiteralPath $summary -Encoding UTF8

    Write-Host ''
    Get-Content -LiteralPath $summary | ForEach-Object { Write-Host $_ }
}

$items=@()
if(Test-Path -LiteralPath $log){$items+=$log}
if(Test-Path -LiteralPath $summary){$items+=$summary}
$recentBuild=Get-ChildItem -LiteralPath $script:PatchesRoot -Filter 'SharpEmu_V74_0_78_APPLY_BUILD_*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($recentBuild){$items+=$recentBuild.FullName}
if($items.Count -ne 0){
    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -LiteralPath $items -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "$script:Tag RESULT ZIP: $zip" -ForegroundColor Green
}
