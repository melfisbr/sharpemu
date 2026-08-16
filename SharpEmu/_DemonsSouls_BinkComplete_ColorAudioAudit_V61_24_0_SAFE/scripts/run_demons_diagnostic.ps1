param(
    [string]$RepositoryRoot,
    [string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$exe=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root "SharpEmu_V61_24_0_DEMONS_BINK_COLOR_AUDIO_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

& (Join-Path $PSScriptRoot 'collect_media_audio_source.ps1') `
    -RepositoryRoot $root `
    -OutputDirectory $out

$stdout=Join-Path $out 'stdout.log'
$stderr=Join-Path $out 'stderr.log'

# Concrete correction #1: do NOT terminate Bink playback only because nominal
# wall-clock duration was reached. Let the decoder/player finish its real frame
# sequence. This is a known runtime switch present in SharpEmu.Libs.
$env:SHARPEMU_BINK_REALTIME_DEADLINE='0'

# Keep the current low-overhead run; do not re-enable destructive AGC tracing.
$env:SHARPEMU_LOG_AGC=$null
$env:SHARPEMU_LOG_AGC_SHADER=$null
$env:SHARPEMU_LOG_VK_RESOURCES=$null
$env:SHARPEMU_LOG_AGC_EPOCH=$null
$env:SHARPEMU_TRACE_GUEST_IMAGES=$null
$env:SHARPEMU_VK_VALIDATION=$null
$env:SHARPEMU_VK_DEBUG_LABELS=$null

Write-Host '[V61.24.0] Bink realtime deadline: DISABLED.'
Write-Host '[V61.24.0] Expected: ps_studios_logo should advance to the final frame instead of switching by wall clock.'
Write-Host '[V61.24.0] Color/audio source evidence will be included in the result ZIP.'
Write-Host '[V61.24.0] Close SharpEmu after observing the videos and post-video screen.'

$p=Start-Process -FilePath $exe -ArgumentList @($Game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru -Wait
$exitCode=$p.ExitCode

$st=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr)}else{''}
$so=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout)}else{''}
$all=$so+"`n"+$st

$logoCompletion=[regex]::Match(
    $all,
    "Bink2 bridge completed: ps_studios_logo\.bk2 after [^\r\n]* at frame (\d+)")
$logoFrame=if($logoCompletion.Success){[int]$logoCompletion.Groups[1].Value}else{-1}

$logoReady=[regex]::Match(
    $all,
    "bink2\.nihav_ready file='ps_studios_logo\.bk2'[^\r\n]*frames=(\d+)[^\r\n]*")
$logoExpected=if($logoReady.Success){[int]$logoReady.Groups[1].Value}else{-1}

$fullFrames=0
if($logoFrame -ge 0 -and $logoExpected -gt 0 -and $logoFrame -ge ($logoExpected-2)) {
    $fullFrames=1
}

$colorLines=($all -split "`r?`n") |
    Select-String -Pattern 'bink2.nihav_ready|bink2.color_range_auto|fallback_chroma|uv_swap|matrix=|range=' |
    ForEach-Object {$_.Line}
$colorLines | Set-Content -LiteralPath (Join-Path $out 'COLOR_RUNTIME.txt') -Encoding UTF8

$audioLines=($all -split "`r?`n") |
    Select-String -Pattern 'ajm\.|audio_out2\.|AudioOut|sceAjm|pcm|decode' |
    ForEach-Object {$_.Line}
$audioLines | Set-Content -LiteralPath (Join-Path $out 'AUDIO_RUNTIME.txt') -Encoding UTF8

@(
    'version=61.24.0',
    "exit_code=$exitCode",
    'bink_realtime_deadline_forced=0',
    "ps_logo_expected_frames=$logoExpected",
    "ps_logo_completion_frame=$logoFrame",
    "ps_logo_full_frames=$fullFrames",
    "bink_completed=$(([regex]::Matches($all,'Bink2 bridge completed:')).Count)",
    "clock_catchup=$(([regex]::Matches($all,'bink2.clock_catchup')).Count)",
    "realtime_deadline_hits=$(([regex]::Matches($all,'bink2.realtime_deadline')).Count)",
    "audio_zero_pcm=$(([regex]::Matches($all,'audio_out2.port-zero-pcm')).Count)",
    "audio_nonzero_pcm=$(([regex]::Matches($all,'audio_out2.port-nonzero-pcm')).Count)",
    "ajm_module=$(([regex]::Matches($all,'ajm.summary.module-register')).Count)",
    "ajm_instance=$(([regex]::Matches($all,'ajm.summary.instance')).Count)",
    "ajm_decode=$(([regex]::Matches($all,'ajm.*decode')).Count)",
    "device_lost=$([int]$all.Contains('deviceLost=True'))"
) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

$focus=($all -split "`r?`n") |
    Select-String -Pattern 'ps_studios_logo|logo_intro|logo_intro_loop|Bink2 bridge completed|direct_boot_completed|color_range_auto|fallback_chroma|audio_out2|ajm\.|deviceLost' |
    ForEach-Object {$_.Line}
$focus | Set-Content -LiteralPath (Join-Path $out 'FOCUS.txt') -Encoding UTF8

$zip="$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.24.0] RESULT: $zip"
