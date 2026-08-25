param()
. (Join-Path $PSScriptRoot 'common.ps1');$s=Read-State 4;$text=Get-Content $s.runtime_log -Raw;$patches=Get-PatchesRoot
function V([string]$p){$m=[regex]::Matches($text,$p);if($m.Count){$m[$m.Count-1].Groups[1].Value}else{'-1'}}
$dl=([regex]::Matches($text,'ErrorDeviceLost|dropping subsequent guest GPU work')).Count
$line=([regex]::Matches($text,'\[V74\.0\.118\.0\]\[RESIDENT_SHADER\][^\r\n]*')|Select-Object -Last 1).Value
function F([string]$n){$m=[regex]::Match($line,[regex]::Escape($n)+'=(\d+)');if($m.Success){$m.Groups[1].Value}else{'-1'}}
$fps=V 'observed_fps=([0-9\.,]+)';$draws=V 'observed_draws=([0-9\.,]+)'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$sum=Join-Path $patches "SharpEmu_V74_0_118_1_1_SUMMARY_$stamp.txt";$zip=Join-Path $patches "SharpEmu_V74_0_118_1_1_RESULT_$stamp.zip"
$assessment=if($dl){'FAIL_DEVICE_LOST_ROLLBACK'}elseif(-not$line){'RESIDENT_SHADER_NOT_TRIGGERED'}else{'GPU_RESIDENT_SHADER_ACTIVE_MEASURE_FPS'}
@("assessment=$assessment","device_lost_count=$dl","observed_fps=$fps","observed_draws=$draws",
"shader_lookups=$(F 'lookups')","shader_address_hits=$(F 'address_hits')","shader_content_changes=$(F 'content_changes')",
"shader_digest_hits=$(F 'digest_hits')","shader_registered=$(F 'registered')","resident_shader_count=$(F 'resident')",
"compute_pipeline_fast_hits=$(F 'compute_pipeline_fast_hits')","graphics_pipeline_fast_hits=$(F 'graphics_pipeline_fast_hits')",
"shader_module_create_saved=$(F 'module_create_saved')","shader_reference_hits=$(F 'reference_hits')",
"shader_exact_compare_hits=$(F 'exact_compare_hits')","shader_compare_mb_saved=$(F 'compare_mb_saved')",
"graphics_allocfree_hits=$(F 'graphics_allocfree_hits')","graphics_string_builds_avoided=$(F 'graphics_string_builds_avoided')",
"shader_fallbacks=$(F 'fallbacks')",'includes_v11716_descriptor_cache=1',
'allocation_free_graphics_pipeline_fastpath=1','shader_reference_fastpath=1',
'vkimage_change=0','buffer_change=0','queue_change=0','submit_change=0','barrier_change=0')|Set-Content $sum
Compress-Archive -LiteralPath @($s.runtime_log,$sum,$s.raw_stdout,$s.raw_stderr) -DestinationPath $zip -Force
Save-State 5 'ANALYSIS_COMPLETED' @{summary=$sum;result_zip=$zip;assessment=$assessment}
Get-Content $sum;Write-Tag "RESULT=$zip"
