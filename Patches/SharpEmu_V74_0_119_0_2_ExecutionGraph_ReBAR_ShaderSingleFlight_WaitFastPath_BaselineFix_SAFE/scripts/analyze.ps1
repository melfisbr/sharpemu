param()
. (Join-Path $PSScriptRoot 'common.ps1')
$s=Read-State 4
$patches=Get-PatchesRoot
$log=[string]$s.runtime_log
$text=Get-Content $log -Raw

function PD([string]$v){
    $d=0.0
    if([double]::TryParse($v.Replace(',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)){return $d}
    return -1.0
}
function LastLine([string]$rx){
    $m=[regex]::Matches($text,$rx,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m.Count){return $m[$m.Count-1].Value};return ''
}
function FieldI([string]$line,[string]$name){
    $m=[regex]::Match($line,[regex]::Escape($name)+'=(\d+)')
    if($m.Success){return [long]$m.Groups[1].Value};return -1
}
function FieldD([string]$line,[string]$name){
    $m=[regex]::Match($line,[regex]::Escape($name)+'=([0-9]+(?:[\.,][0-9]+)?)')
    if($m.Success){return PD $m.Groups[1].Value};return -1.0
}
function LastD([string]$rx){
    $m=[regex]::Matches($text,$rx,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m.Count){return PD $m[$m.Count-1].Groups[1].Value};return -1.0
}
function MaxD([string]$rx){
    $m=[regex]::Matches($text,$rx,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $max=-1.0;foreach($x in $m){$v=PD $x.Groups[1].Value;if($v-gt$max){$max=$v}};return $max
}
function MedianD([string]$rx){
    $m=[regex]::Matches($text,$rx,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not$m.Count){return -1.0}
    $v=@();foreach($x in $m){$v+=,(PD $x.Groups[1].Value)};$v=@($v|Sort-Object);$n=$v.Count
    if($n%2){return [double]$v[[int]($n/2)]};return ([double]$v[$n/2-1]+[double]$v[$n/2])/2
}

$deviceLost=([regex]::Matches($text,'ErrorDeviceLost|dropping subsequent guest GPU work',[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
$fps=LastD 'observed_fps=([0-9]+(?:[\.,][0-9]+)?)'
$draws=LastD 'observed_draws=([0-9]+(?:[\.,][0-9]+)?)'
$cpu=LastD 'observed_cpu=([0-9]+(?:[\.,][0-9]+)?)'
$gpu=LastD 'observed_gpu=([0-9]+(?:[\.,][0-9]+)?)'

$resident=LastLine '\[V74\.0\.118\.0\]\[RESIDENT_SHADER\][^\r\n]*'
$exec=LastLine '\[V74\.0\.119\.0\]\[EXECUTION_GRAPH\][^\r\n]*'
$rebar=LastLine '\[V74\.0\.119\.0\]\[REBAR_GLOBAL_DIRECT\][^\r\n]*'
$render=LastLine '\[PERF\]\[RENDER\][^\r\n]*'

$slowCount=([regex]::Matches($text,'\[V74\.0\.27\]\[SLOW_WAIT_PRODUCER\]')).Count
$producerMedian=MedianD '\[V74\.0\.27\]\[SLOW_WAIT_PRODUCER\][^\r\n]*producer_complete_ms=([0-9]+(?:[\.,][0-9]+)?)'
$producerMax=MaxD '\[V74\.0\.27\]\[SLOW_WAIT_PRODUCER\][^\r\n]*producer_complete_ms=([0-9]+(?:[\.,][0-9]+)?)'
$postMedian=MedianD '\[V74\.0\.27\]\[SLOW_WAIT_PRODUCER\][^\r\n]*post_complete_wait_ms=([0-9]+(?:[\.,][0-9]+)?)'
$payloadAvg=LastD 'PAYLOAD_BATCH_SUBMIT[^\r\n]*avg=([0-9]+(?:[\.,][0-9]+)?)'
$privateMb=LastD '\[V74\.0\.8\.1\]\[MEM\][^\r\n]*private_mb=(\d+)'
$alloc2s=LastD '\[V74\.0\.8\.1\]\[MEM\][^\r\n]*alloc2s_mb=(\d+)'

$assessment=if($deviceLost-gt0){
    'FAIL_DEVICE_LOST_ROLLBACK'
}elseif($fps-gt0.8){
    'EXECUTION_GRAPH_PERFORMANCE_GAIN'
}elseif($render){
    'EXECUTION_GRAPH_ACTIVE_USE_RENDER_PHASE_PROFILE_FOR_NEXT_STRUCTURAL_STEP'
}else{
    'EXECUTION_GRAPH_ACTIVE_RENDER_PROFILE_MISSING'
}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$sum=Join-Path $patches "SharpEmu_V74_0_119_0_2_SUMMARY_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_119_0_2_RESULT_$stamp.zip"

@(
    "assessment=$assessment",
    "device_lost_count=$deviceLost",
    "rollback_recommended=$(if($deviceLost){1}else{0})",
    "observed_fps=$fps",
    ("fps_gain_vs_v11801_x={0:F2}" -f $(if($fps-gt0){$fps/0.6}else{-1})),
    "observed_draws=$draws",
    "observed_cpu=$cpu",
    "observed_gpu=$gpu",
    "resident_reference_hits=$(FieldI $resident 'reference_hits')",
    "resident_byte_compare_hits=$(FieldI $resident 'byte_compare_hits')",
    ("resident_compare_avoided_mb={0:F2}" -f (FieldD $resident 'compare_avoided_mb')),
    "resident_compute_pipeline_fast_hits=$(FieldI $resident 'compute_pipeline_fast_hits')",
    "resident_graphics_pipeline_fast_hits=$(FieldI $resident 'graphics_pipeline_fast_hits')",
    "execution_wait_fast=$(FieldI $exec 'wait_fast')",
    "execution_wait_full=$(FieldI $exec 'wait_full')",
    "shader_singleflight_waits=$(FieldI $exec 'shader_waits')",
    "shader_singleflight_dedup=$(FieldI $exec 'shader_dedup')",
    "rebar_direct_count=$(FieldI $rebar 'count')",
    ("rebar_direct_mb={0:F2}" -f (FieldD $rebar 'mb')),
    "rebar_fallbacks=$(FieldI $rebar 'fallbacks')",
    "slow_wait_producer_count=$slowCount",
    ("producer_complete_median_ms={0:F3}" -f $producerMedian),
    ("producer_complete_max_ms={0:F3}" -f $producerMax),
    ("post_complete_wait_median_ms={0:F3}" -f $postMedian),
    "payload_batch_average_last=$payloadAvg",
    "private_last_mb=$privateMb",
    "alloc2s_last_mb=$alloc2s",
    "render_phase_last=$render",
    'shader_resident_max=1024',
    'v11713_global_residency=0',
    'queue_order_change=0',
    'submit_change=0',
    'barrier_change=0',
    'image_lifetime_change=0',
    'dual_vkqueue=0',
    'long_term_target_fps=60'
)|Set-Content $sum -Encoding UTF8

$files=@($log,$sum,$s.raw_stdout,$s.raw_stderr,
    (Join-Path (Get-PackageRoot) 'reference\ARCHITECTURE_V119_0.txt'),
    (Join-Path (Get-PackageRoot) 'reference\STATIC_VALIDATION.txt'))
foreach($pat in @('SharpEmu_V74_0_119_0_2_PRECHECK_*.txt','SharpEmu_V74_0_119_0_2_BUILD_*.log')){
    $f=Get-ChildItem $patches -Filter $pat|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($f){$files+=$f.FullName}
}
Compress-Archive -LiteralPath $files -DestinationPath $zip -Force
Save-State 5 'ANALYSIS_COMPLETED' @{summary=$sum;result_zip=$zip;assessment=$assessment}
Get-Content $sum
Write-Tag "RESULT=$zip"
