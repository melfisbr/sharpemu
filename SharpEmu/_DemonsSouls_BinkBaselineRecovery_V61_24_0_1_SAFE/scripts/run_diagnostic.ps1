param(
    [string]$RepositoryRoot,
    [string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root "SharpEmu_V61_24_0_1_BINK_BASELINE_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
& (Join-Path $PSScriptRoot 'collect_exact_media_baseline.ps1') -RepositoryRoot $root -OutputDirectory $out

$exe=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$stdout=Join-Path $out 'stdout.log'
$stderr=Join-Path $out 'stderr.log'

# Do not force a stale/nonexistent deadline feature. If the current runtime has
# the switch, disabling it is harmless; otherwise this variable is ignored.
$env:SHARPEMU_BINK_REALTIME_DEADLINE='0'

# Keep expensive AGC trace families disabled for this media-focused run.
$env:SHARPEMU_LOG_AGC=$null
$env:SHARPEMU_LOG_AGC_SHADER=$null
$env:SHARPEMU_LOG_VK_RESOURCES=$null
$env:SHARPEMU_LOG_AGC_EPOCH=$null
$env:SHARPEMU_TRACE_GUEST_IMAGES=$null
$env:SHARPEMU_VK_VALIDATION=$null
$env:SHARPEMU_VK_DEBUG_LABELS=$null

Write-Host '[V61.24.0.1] Launching current rollback baseline.'
Write-Host '[V61.24.0.1] Observe first movie completion, second movie, color, audio and post-video state.'
Write-Host '[V61.24.0.1] Close SharpEmu after the post-video state is clearly reached.'

$p=Start-Process -FilePath $exe -ArgumentList @($Game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru -Wait
$exitCode=$p.ExitCode

$all=''
if(Test-Path -LiteralPath $stdout){$all += [IO.File]::ReadAllText($stdout)}
if(Test-Path -LiteralPath $stderr){$all += "`n"+[IO.File]::ReadAllText($stderr)}

$ready=[regex]::Match($all,"bink2\.nihav_ready file='ps_studios_logo\.bk2'[^\r\n]*frames=(\d+)")
$done=[regex]::Match($all,"Bink2 bridge completed: ps_studios_logo\.bk2[^\r\n]*at frame (\d+)")
$expected=if($ready.Success){[int]$ready.Groups[1].Value}else{-1}
$actual=if($done.Success){[int]$done.Groups[1].Value}else{-1}
$complete=[int]($expected -gt 0 -and $actual -ge ($expected-2))

$focus=($all -split "`r?`n") | Select-String -Pattern `
    'ps_studios_logo|logo_intro|logo_intro_loop|Bink2 bridge completed|direct_boot_completed|clock_catchup|deadline|color_range|uv_swap|matrix=|range=|ajm\.|audio_out|AudioOut|pcm|deviceLost|wait_suspended|wait_stale' |
    ForEach-Object {$_.Line}
$focus | Set-Content -LiteralPath (Join-Path $out 'RUNTIME_FOCUS.txt') -Encoding UTF8

@(
    'version=61.24.0.1',
    "exit_code=$exitCode",
    "ps_logo_expected_frames=$expected",
    "ps_logo_completion_frame=$actual",
    "ps_logo_near_final_frame=$complete",
    "bink_completed_count=$(([regex]::Matches($all,'Bink2 bridge completed:')).Count)",
    "clock_catchup_count=$(([regex]::Matches($all,'bink2.clock_catchup')).Count)",
    "deadline_marker_runtime_count=$(([regex]::Matches($all,'realtime_deadline')).Count)",
    "ajm_module_count=$(([regex]::Matches($all,'ajm.summary.module-register')).Count)",
    "ajm_instance_count=$(([regex]::Matches($all,'ajm.summary.instance')).Count)",
    "ajm_decode_mentions=$(([regex]::Matches($all,'ajm.*decode')).Count)",
    "audio_zero_pcm=$(([regex]::Matches($all,'audio_out2.port-zero-pcm')).Count)",
    "audio_nonzero_pcm=$(([regex]::Matches($all,'audio_out2.port-nonzero-pcm')).Count)",
    "wait_suspended=$(([regex]::Matches($all,'agc.wait_suspended')).Count)",
    "wait_stale=$(([regex]::Matches($all,'agc.wait_stale')).Count)",
    "device_lost=$([int]$all.Contains('deviceLost=True'))"
) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

$zip="$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.24.0.1] RESULT: $zip"
