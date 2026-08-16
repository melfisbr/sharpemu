param([string]$RepositoryRoot,[string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r
$exe=Join-Path $r 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if(!(Test-Path -LiteralPath $exe -PathType Leaf)){throw "Executable missing: $exe"}
if(!(Test-Path -LiteralPath $Game -PathType Leaf)){throw "Game missing: $Game"}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $r "SharpEmu_V61_24_3_BINK_FALLBACK_CHROMA_$stamp"
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'stdout.log';$stderr=Join-Path $out 'stderr.log'

# Keep the previously validated full-video behavior.
$env:SHARPEMU_BINK_REALTIME_DEADLINE='0'

# V61.24.1/2 proved persistent FFmpeg swscale initializes but times out after
# 5000 ms on the first frame of every movie. Do not pay that failure penalty.
$env:SHARPEMU_BINK_FFMPEG_COLOR='0'
$env:SHARPEMU_BINK_FFMPEG_UV_SWAP=$null

# Apply U/V correction to the path that actually presents the frames: LUT fallback.
# This existing code re-runs conversion with vPlane/uPlane in reversed order.
$env:SHARPEMU_BINK_FORCE_UV_SWAP='1'
$env:SHARPEMU_BINK_AUTO_UV_REPAIR='0'
$env:SHARPEMU_NIHAV_UV_SWAP='0'
$env:SHARPEMU_NIHAV_AUTO_RANGE='1'
$env:SHARPEMU_LOG_BINK2='1'

# Avoid unrelated high-volume diagnostics.
$env:SHARPEMU_LOG_AJM=$null
$env:SHARPEMU_LOG_AUDIO=$null
$env:SHARPEMU_LOG_AUDIOOUT=$null
$env:SHARPEMU_LOG_AUDIOOUT2=$null
$env:SHARPEMU_LOG_AGC=$null
$env:SHARPEMU_LOG_AGC_SHADER=$null
$env:SHARPEMU_LOG_VK_RESOURCES=$null

Write-Host '[V61.24.3] FFmpeg color path: OFF (V61.24.2 proved first-frame timeout).'
Write-Host '[V61.24.3] Actual LUT fallback U/V swap: FORCED ON.'
Write-Host '[V61.24.3] Full Bink playback behavior retained.'
Write-Host '[V61.24.3] Compare PlayStation Studios colors with V61.24.2, then close SharpEmu.'

$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait

$all=''
if(Test-Path -LiteralPath $stdout){$all+=[IO.File]::ReadAllText($stdout)}
if(Test-Path -LiteralPath $stderr){$all+="`n"+[IO.File]::ReadAllText($stderr)}

($all -split "`r?`n" |
    Select-String -Pattern 'bink2\.|Bink2 bridge|fallback_chroma|ffmpeg_color|color_range|uv_swap|deviceLost' |
    ForEach-Object{$_.Line}) |
    Set-Content -LiteralPath (Join-Path $out 'FOCUS.txt') -Encoding UTF8

@(
    'version=61.24.3',
    "exit_code=$($p.ExitCode)",
    "forced_uv_markers=$(([regex]::Matches($all,'bink2\.fallback_chroma_forced uv_swap=True')).Count)",
    "ffmpeg_ready=$(([regex]::Matches($all,'bink2\.ffmpeg_color_ready')).Count)",
    "ffmpeg_fallback=$(([regex]::Matches($all,'bink2\.ffmpeg_color_fallback')).Count)",
    "bink_completed=$(([regex]::Matches($all,'Bink2 bridge completed:')).Count)",
    "ps_logo_completion=$(([regex]::Matches($all,'Bink2 bridge completed: ps_studios_logo\.bk2')).Count)",
    "device_lost=$([int]$all.Contains('deviceLost=True'))"
) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

$zip="$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.24.3] RESULT: $zip"
