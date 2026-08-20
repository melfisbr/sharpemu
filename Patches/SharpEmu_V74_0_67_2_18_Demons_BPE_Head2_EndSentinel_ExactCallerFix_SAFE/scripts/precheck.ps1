. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$frontendPath=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'

foreach($path in @($exceptionsPath,$agcPath,$bridgePath,$frontendPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing required source: $path"
    }
}

$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$f=Normalize-Lf ([IO.File]::ReadAllText($frontendPath))

$v217Markers=@(
    'V74.0.67.2.17 size-aware large-array admission',
    'V74.0.67.2.17 small WRITE_DATA packet position',
    'V74.0.67.2.17 producer completion latency')
$v217Present=0
foreach($marker in $v217Markers){
    if($a.Contains($marker)){$v217Present++}
}

$v217State=if($v217Present-eq $v217Markers.Count){
    'Applied'
}elseif($v217Present-eq 0){
    'Ready'
}else{
    'Partial'
}

$checks=[ordered]@{
    bpe_v211=$e.Contains('V74.0.67.2.11 BPE end-sentinel return repair')
    bpe_v212=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    bpe_base_method=$e.Contains('TryRecoverDemonBpeLowSentinelListFaultV74067241')
    v215_ram_ttl=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    v214_dlss=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    v215_frontend=$f.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.18] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host "[V74.0.67.2.18] v217_state=$v217State"
if($v217State-eq 'Partial'){$failed=$true}

$already=$e.Contains('V74.0.67.2.18 BPE head2 end-sentinel recovery')
Write-Host "[V74.0.67.2.18] bpe_head2_already=$($already.ToString().ToLowerInvariant())"

if(!$already){
    $counter=@'
	private static int _demonBpeLowSentinelRecoveriesV74067241; // V74.0.67.2.4.1 BPE low-sentinel list recovery
'@
    $call=@'
			// V74.0.67.2.4.1 BPE low-sentinel list recovery
			if (exceptionCode == 3221225477u &&
				TryRecoverDemonBpeLowSentinelListFaultV74067241(
					exceptionRecord,
					contextRecord,
					rip))
			{
				return -1;
			}
'@
    $method='	// V74.0.67.2.4.1 BPE low-sentinel linked-list recovery.'

    $counterCount=Count-Ordinal -Text $e -Needle $counter
    $callCount=Count-Ordinal -Text $e -Needle $call
    $methodCount=Count-Ordinal -Text $e -Needle $method

    Write-Host "[V74.0.67.2.18] bpe_counter_anchor_count=$counterCount"
    Write-Host "[V74.0.67.2.18] bpe_handler_anchor_count=$callCount"
    Write-Host "[V74.0.67.2.18] bpe_method_anchor_count=$methodCount"

    if($counterCount-ne 1 -or $callCount-ne 1 -or $methodCount-ne 1){
        $failed=$true
    }
}

Write-Host '[V74.0.67.2.18] crash_signature=target-0xA+rcx2+rax2+primary-r14+head2'
Write-Host '[V74.0.67.2.18] caller_contract=cmp-return-against-rbp-minus-0xC70-payload'
Write-Host '[V74.0.67.2.18] recovery_semantics=return-canonical-payload-end-sentinel'
Write-Host '[V74.0.67.2.18] absolute_guest_address_gate=false'
Write-Host '[V74.0.67.2.18] dlss_change=false'
Write-Host '[V74.0.67.2.18] submission_hard_cap_change=false'

if($failed){throw '[V74.0.67.2.18] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.18] PRECHECK PASSED.'
