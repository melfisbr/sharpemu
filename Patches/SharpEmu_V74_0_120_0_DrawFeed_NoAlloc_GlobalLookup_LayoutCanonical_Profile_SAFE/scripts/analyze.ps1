param()
. (Join-Path $PSScriptRoot 'common.ps1')
$state=Read-State 4
$patches=Get-PatchesRoot
$log=[string]$state.runtime_log
$text=Get-Content -LiteralPath $log -Raw

function Parse-Decimal([string]$Value){
    $result=0.0
    if([double]::TryParse(
        $Value.Replace(',','.'),
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$result)){return $result}
    return -1.0
}
function Get-LastDecimal([string]$Pattern){
    $matches=[regex]::Matches($text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($matches.Count-eq0){return -1.0}
    Parse-Decimal $matches[$matches.Count-1].Groups[1].Value
}
function Get-LastLine([string]$Pattern){
    $matches=[regex]::Matches($text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($matches.Count-eq0){return ''}
    $matches[$matches.Count-1].Value
}
function Get-FieldInt([string]$Line,[string]$Name){
    if(-not$Line){return -1}
    $match=[regex]::Match($Line,[regex]::Escape($Name)+'=(\d+)')
    if(-not$match.Success){return -1}
    [long]$match.Groups[1].Value
}
function Get-PhaseStats([string]$PhaseName){
    $pattern='\[V74\.0\.56\.23\]\[DRAW_RESOURCE_PHASES\][^\r\n]*'+
        [regex]::Escape($PhaseName)+'_ms=([0-9]+(?:[\.,][0-9]+)?)'
    $matches=[regex]::Matches($text,$pattern)
    if($matches.Count-eq0){
        return [pscustomobject]@{Count=0;Median=-1.0;Max=-1.0}
    }
    $values=@()
    foreach($match in $matches){
        $values+=,(Parse-Decimal $match.Groups[1].Value)
    }
    $values=@($values|Sort-Object)
    $count=$values.Count
    $median=if(($count%2)-eq1){
        [double]$values[[int]($count/2)]
    }else{
        ([double]$values[$count/2-1]+[double]$values[$count/2])/2.0
    }
    [pscustomobject]@{
        Count=$count
        Median=$median
        Max=[double]$values[-1]
    }
}

$deviceLost=[regex]::Matches(
    $text,
    'ErrorDeviceLost|dropping subsequent guest GPU work',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase).Count

$fps=Get-LastDecimal 'observed_fps=([0-9]+(?:[\.,][0-9]+)?)'
$draws=Get-LastDecimal 'observed_draws=([0-9]+(?:[\.,][0-9]+)?)'
$cpu=Get-LastDecimal 'observed_cpu=([0-9]+(?:[\.,][0-9]+)?)'
$gpu=Get-LastDecimal 'observed_gpu=([0-9]+(?:[\.,][0-9]+)?)'

$hot=Get-LastLine '\[V74\.0\.120\.0\]\[DRAW_HOTPATH\][^\r\n]*'
$resident=Get-LastLine '\[V74\.0\.118\.0\]\[RESIDENT_SHADER\][^\r\n]*'
$descriptor=Get-LastLine '\[V74\.0\.117\.16\]\[DESCRIPTOR_SET_CACHE\][^\r\n]*'
$rebar=Get-LastLine '\[V74\.0\.119\.0\]\[REBAR_GLOBAL_DIRECT\][^\r\n]*'
$render=Get-LastLine '\[PERF\]\[RENDER\][^\r\n]*'

$texture=Get-PhaseStats 'texture'
$global=Get-PhaseStats 'global'
$vertex=Get-PhaseStats 'vertex'
$descriptorPhase=Get-PhaseStats 'descriptor'
$pipeline=Get-PhaseStats 'pipeline'
$total=Get-PhaseStats 'total'

$baselineFps=0.4
$baselineDraws=200.0
$fpsGain=if($fps-gt0){$fps/$baselineFps}else{-1.0}
$drawGain=if($draws-gt0){$draws/$baselineDraws}else{-1.0}

$assessment=if($deviceLost-gt0){
    'FAIL_DEVICE_LOST_ROLLBACK'
}elseif(-not$hot){
    'V120_HOTPATH_NOT_TRIGGERED'
}elseif($fps-ge58){
    'TARGET_60FPS_RANGE_REACHED'
}elseif($fps-gt0.6-or$draws-gt300){
    'DRAW_FEED_STRUCTURAL_GAIN'
}elseif($global.Max-ge20){
    'GLOBAL_RESOURCE_PHASE_STILL_DOMINANT'
}elseif($texture.Max-ge20){
    'TEXTURE_RESOURCE_PHASE_STILL_DOMINANT'
}elseif($descriptorPhase.Max-ge10){
    'DESCRIPTOR_UPDATE_PHASE_STILL_SIGNIFICANT'
}else{
    'DRAW_CPU_OVERHEAD_REDUCED_NEXT_USE_PHASE_PROFILE'
}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$summary=Join-Path $patches "SharpEmu_V74_0_120_0_SUMMARY_$stamp.txt"
$result=Join-Path $patches "SharpEmu_V74_0_120_0_RESULT_$stamp.zip"

@(
    "assessment=$assessment",
    "device_lost_count=$deviceLost",
    "rollback_recommended=$(if($deviceLost-gt0){1}else{0})",
    "observed_fps=$fps",
    ("fps_gain_vs_v11801_x={0:F2}" -f $fpsGain),
    "observed_draws=$draws",
    ("draw_gain_vs_v11801_x={0:F2}" -f $drawGain),
    "observed_cpu=$cpu",
    "observed_gpu=$gpu",
    "readonly_prepare_fast_returns=$(Get-FieldInt $hot 'readonly_prepare')",
    "single_writable_prepare_fastpaths=$(Get-FieldInt $hot 'single_writable_prepare')",
    "global_allocation_lookups=$(Get-FieldInt $hot 'global_lookups')",
    "global_binary_steps=$(Get-FieldInt $hot 'global_binary_steps')",
    "global_linear_candidates_avoided=$(Get-FieldInt $hot 'linear_candidates_avoided')",
    "zero_vertex_noalloc=$(Get-FieldInt $hot 'zero_vertex_noalloc')",
    "single_vertex_noalloc=$(Get-FieldInt $hot 'single_vertex_noalloc')",
    "feedback_probes=$(Get-FieldInt $hot 'feedback_probes')",
    "resource_layout_cache_hits=$(Get-FieldInt $hot 'resource_layout_hits')",
    "resource_layout_cache_misses=$(Get-FieldInt $hot 'resource_layout_misses')",
    "target_layout_cache_hits=$(Get-FieldInt $hot 'target_layout_hits')",
    "target_layout_cache_misses=$(Get-FieldInt $hot 'target_layout_misses')",
    "blend_layout_cache_hits=$(Get-FieldInt $hot 'blend_layout_hits')",
    "blend_layout_cache_misses=$(Get-FieldInt $hot 'blend_layout_misses')",
    "zero_vertex_layout_hits=$(Get-FieldInt $hot 'zero_vertex_layout')",
    "draw_resource_phase_samples=$($total.Count)",
    ("draw_total_median_ms={0:F3}" -f $total.Median),
    ("draw_total_max_ms={0:F3}" -f $total.Max),
    ("draw_texture_median_ms={0:F3}" -f $texture.Median),
    ("draw_texture_max_ms={0:F3}" -f $texture.Max),
    ("draw_global_median_ms={0:F3}" -f $global.Median),
    ("draw_global_max_ms={0:F3}" -f $global.Max),
    ("draw_vertex_median_ms={0:F3}" -f $vertex.Median),
    ("draw_vertex_max_ms={0:F3}" -f $vertex.Max),
    ("draw_descriptor_median_ms={0:F3}" -f $descriptorPhase.Median),
    ("draw_descriptor_max_ms={0:F3}" -f $descriptorPhase.Max),
    ("draw_pipeline_median_ms={0:F3}" -f $pipeline.Median),
    ("draw_pipeline_max_ms={0:F3}" -f $pipeline.Max),
    "render_phase_last=$render",
    "resident_shader_last=$resident",
    "descriptor_cache_last=$descriptor",
    "rebar_global_last=$rebar",
    'vkimage_change=0',
    'texture_lifetime_change=0',
    'buffer_content_change=0',
    'queue_change=0',
    'submit_change=0',
    'barrier_change=0',
    'pair2_change=0',
    'dual_vkqueue=0',
    'long_term_target_fps=60'
)|Set-Content -LiteralPath $summary -Encoding UTF8

$files=@(
    $log,
    $summary,
    (Join-Path (Get-PackageRoot) 'reference\SOURCE_REVIEW_V120_0.txt'),
    (Join-Path (Get-PackageRoot) 'reference\STATIC_TRANSFORM_VALIDATION.txt')
)
foreach($optional in @([string]$state.raw_stdout,[string]$state.raw_stderr)){
    if($optional-and(Test-Path -LiteralPath $optional)){$files+=$optional}
}
$build=Get-ChildItem -LiteralPath $patches -Filter 'SharpEmu_V74_0_120_0_BUILD_*.log'|
    Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($build){$files+=$build.FullName}
if(Test-Path -LiteralPath $result){Remove-Item -LiteralPath $result -Force}
Compress-Archive -LiteralPath $files -DestinationPath $result -CompressionLevel Optimal

Save-State 5 'ANALYSIS_COMPLETED' @{
    runtime_log=$log
    summary=$summary
    result_zip=$result
    assessment=$assessment
}
Get-Content -LiteralPath $summary|ForEach-Object{Write-Host $_}
Write-Tag "RESULT PACKAGE=$result"
