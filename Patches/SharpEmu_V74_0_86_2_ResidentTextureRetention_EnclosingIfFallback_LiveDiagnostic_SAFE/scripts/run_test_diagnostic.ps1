param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
if(-not($s.Agc.Contains('SHARPEMU_V74_0_86_2_RESIDENT_TEXTURE_RETENTION_SEMANTIC_CACHE_HIT') -and $s.Presenter.Contains('SHARPEMU_V74_0_86_2_RESIDENT_TEXTURE_RETENTION_SEMANTIC_CACHE_HIT'))){throw "$script:Tag V86 not applied. Run RUN_3 first."}
$exe=Find-SharpEmuExe;if($null -eq $exe){throw "$script:Tag SharpEmu executable not found. Build first."}
$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin';if(-not(Test-Path -LiteralPath $eboot)){throw "$script:Tag eboot absent: $eboot"}
foreach($n in @(
 'SHARPEMU_KYTY_PM4_BLOCKED_SCHEDULER','SHARPEMU_KYTY_INLINE_WRITE_DATA',
 'SHARPEMU_RELEASE_MEM_QUEUE_COMPLETION_ONLY','SHARPEMU_LOCAL_TEXTURE_PAYLOAD_DEDUP',
 'SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE','SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB',
 'SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS')){Remove-Item -LiteralPath ("Env:"+$n) -ErrorAction SilentlyContinue}
$ts=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_86_2_RESIDENT_RETENTION_${ts}.log")
$summary=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_86_2_RESIDENT_RETENTION_SUMMARY_${ts}.txt")
$zip=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_86_2_RESIDENT_RETENTION_RESULT_${ts}.zip")
Write-Host "$script:Tag RuntimeLog=$log"
Write-Host "$script:Tag Summary=$summary"
Write-Host "$script:Tag ResultZip=$zip"
Write-Host "$script:Tag LIVE LOG ENABLED: the .log is written while SharpEmu is running." -ForegroundColor Green
'' | Set-Content -LiteralPath $log -Encoding UTF8
$oldEap=$ErrorActionPreference
$ErrorActionPreference='Continue'
& $exe $eboot 2>&1 | Tee-Object -FilePath $log -Append
$code=$LASTEXITCODE
$ErrorActionPreference=$oldEap
if(-not(Test-Path -LiteralPath $log)){throw "$script:Tag runtime log was not created: $log"}
$t=[System.IO.File]::ReadAllText($log)
function MaxCounter([string]$pattern){$max=0L;foreach($m in [regex]::Matches($t,$pattern)){try{$v=[int64]$m.Groups[1].Value;if($v-gt$max){$max=$v}}catch{}};return $max}
function CountMatches([string]$pattern){return [regex]::Matches($t,$pattern).Count}
function StatMs([string]$pattern){$vals=New-Object System.Collections.Generic.List[double];foreach($m in [regex]::Matches($t,$pattern)){try{$vals.Add([double]::Parse($m.Groups[1].Value.Replace(',','.'),[System.Globalization.CultureInfo]::InvariantCulture))}catch{}};if($vals.Count-eq0){return 'count=0'};$avg=($vals|Measure-Object -Average).Average;$mx=($vals|Measure-Object -Maximum).Maximum;return ('count={0} avg_ms={1:F3} max_ms={2:F3}' -f $vals.Count,$avg,$mx)}
$largePath=CountMatches 'large_texture_cpu_snapshot'
$largeReuse=CountMatches 'large_texture_snapshot_reuse'
$largeEstimated=$largePath-$largeReuse;if($largeEstimated -lt 0){$largeEstimated=0}
$lines=New-Object System.Collections.Generic.List[string]
$lines.Add('[V74.0.86.2] Resident Texture Retention + Semantic Cache-Hit Bridge Release diagnostic')
$lines.Add("ExitCode=$code")
$lines.Add('runtime_log_present='+[bool](Test-Path -LiteralPath $log))
$lines.Add('first_frame='+(CountMatches 'presented first frame'))
$lines.Add('device_lost='+(CountMatches '(?i)device lost|ErrorDeviceLost'))
$lines.Add('cpu_bridge_release_max_counter='+(MaxCounter '\[CPU_BRIDGE_RELEASE\].*?count=(\d+)'))
$lines.Add('cpu_bridge_release_total_mb='+(MaxCounter '\[CPU_BRIDGE_RELEASE\].*?total_released_mb=(\d+)'))
$lines.Add("large_snapshot_path_logged=$largePath")
$lines.Add("large_snapshot_reuse_logged=$largeReuse")
$lines.Add("large_snapshot_estimated_nonreuse=$largeEstimated")
$lines.Add('array_cache_owner_logged='+(CountMatches '\[ARRAY_CACHE_OWNER\]'))
$lines.Add('array_singleflight_reuse_logged='+(CountMatches '\[ARRAY_SINGLEFLIGHT\]'))
$lines.Add('texture_cache_trim_logged='+(CountMatches '\[TEX_CACHE\] trim'))
$lines.Add('local_texture_payload_dedup_max_counter='+(MaxCounter '\[LOCAL_TEXTURE_PAYLOAD_DEDUP\].*?count=(\d+)'))
$lines.Add('release_queue_only_max_counter='+(MaxCounter '\[RELEASE_QUEUE_ONLY\].*?count=(\d+)'))
$lines.Add('adaptive_unified_max_counter='+(MaxCounter '\[ADAPTIVE_UNIFIED_COMPUTE\].*?count=(\d+)'))
$lines.Add('ordered_visibility_defer_max_counter='+(MaxCounter '\[ORDERED_VISIBILITY_DEFER\].*?count=(\d+)'))
$lines.Add('parser_escape_logged='+(CountMatches '\[PARSER_ESCAPE\]'))
$lines.Add('slow_wait_ms: '+(StatMs 'SLOW_WAIT_PRODUCER.*?waited_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$lines.Add('gate_wait_ms: '+(StatMs 'DEDICATED_WAIT_DRAIN.*?gate_wait_ms=([0-9]+(?:[\.,][0-9]+)?)'))
$alloc=MaxCounter 'alloc2s_mb=(\d+)';$work=MaxCounter 'working_mb=(\d+)';$priv=MaxCounter 'private_mb=(\d+)';$texMb=MaxCounter 'tex_cache_mb=(\d+)'
$lines.Add("mem_max_alloc2s_mb=$alloc")
$lines.Add("mem_max_working_mb=$work")
$lines.Add("mem_max_private_mb=$priv")
$lines.Add("mem_max_tex_cache_mb=$texMb")
$lines.Add('source_defaults: standalone_texture_cache_mb=3072 large_snapshot_ttl_ms=10000 resident_bridge_release=on')
$lines.Add('target_frame_budget_60fps_ms=16.667')
[System.IO.File]::WriteAllLines($summary,$lines,[System.Text.Encoding]::UTF8)
$lines|ForEach-Object{Write-Host "$script:Tag $_"}
try{
 if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
 Compress-Archive -LiteralPath @($log,$summary) -DestinationPath $zip -CompressionLevel Optimal
 Write-Host "$script:Tag RESULT ZIP=$zip" -ForegroundColor Green
}catch{Write-Host "$script:Tag ZIP creation failed, but live log and summary are preserved: $($_.Exception.Message)" -ForegroundColor Yellow}
