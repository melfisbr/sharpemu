param([string]$RepositoryRoot,[string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r
$exe=Join-Path $r 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if(!(Test-Path -LiteralPath $exe)){throw "Executable missing: $exe"}
if(!(Test-Path -LiteralPath $Game)){throw "Game missing: $Game"}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $r "SharpEmu_V61_24_1_COLOR_AUDIO_ROUTE_$stamp"
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'stdout.log';$stderr=Join-Path $out 'stderr.log'

# V61.24.0.1 evidence: all 255 PS Studios frames are decoded (completion index 254).
# Keep frame-complete behavior.
$env:SHARPEMU_BINK_REALTIME_DEADLINE='0'

# Color: current source already contains a persistent FFmpeg swscale YUV420P->BGRA
# path explicitly intended to replace the scalar/LUT conversion. Activate it.
# Keep U/V unswapped first: V70.1 repacks NIHAV side-by-side U|V into true I420.
$env:SHARPEMU_BINK_FFMPEG_COLOR='1'
$env:SHARPEMU_NIHAV_UV_SWAP='0'
$env:SHARPEMU_NIHAV_AUTO_RANGE='1'
$env:SHARPEMU_LOG_BINK2='1'

# Audio: V61.24.0.1 saw AudioOut2 context queries but zero AJM module/instance/decode.
# Turn on the existing AJM/Audio traces to determine whether the game reaches the
# HLE exports or whether import/routing is the missing layer.
$env:SHARPEMU_LOG_AJM='1'
$env:SHARPEMU_LOG_AUDIO='1'
$env:SHARPEMU_LOG_AUDIOOUT='1'
$env:SHARPEMU_LOG_AUDIOOUT2='1'

# Avoid unrelated high-volume GPU traces.
$env:SHARPEMU_LOG_AGC=$null
$env:SHARPEMU_LOG_AGC_SHADER=$null
$env:SHARPEMU_LOG_VK_RESOURCES=$null

Write-Host '[V61.24.1] PS Studios frame-complete mode retained.'
Write-Host '[V61.24.1] FFmpeg swscale color conversion ENABLED; auto range ENABLED; UV swap OFF.'
Write-Host '[V61.24.1] AJM/AudioOut routing trace ENABLED.'
Write-Host '[V61.24.1] Observe color and audio; close SharpEmu after post-video state.'

$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
$all=''
if(Test-Path -LiteralPath $stdout){$all+=[IO.File]::ReadAllText($stdout)}
if(Test-Path -LiteralPath $stderr){$all+="`n"+[IO.File]::ReadAllText($stderr)}
($all -split "`r?`n"|Select-String -Pattern 'bink2\.|Bink2 bridge|ffmpeg|color|range|uv_swap|ajm\.|sceAjm|audio_out|AudioOut|pcm|deviceLost'|ForEach-Object{$_.Line})|Set-Content (Join-Path $out 'FOCUS.txt') -Encoding UTF8
@(
'version=61.24.1',
"exit_code=$($p.ExitCode)",
"ps_logo_complete=$([int]($all -match 'Bink2 bridge completed: ps_studios_logo\.bk2[^\r\n]*frame 254'))",
"ffmpeg_color_mentions=$(([regex]::Matches($all,'ffmpeg',[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count)",
"ajm_initialize=$(([regex]::Matches($all,'ajm\.initialize')).Count)",
"ajm_module=$(([regex]::Matches($all,'ajm\.(summary\.)?module')).Count)",
"ajm_instance=$(([regex]::Matches($all,'ajm\.(summary\.)?instance')).Count)",
"ajm_decode=$(([regex]::Matches($all,'ajm.*decode')).Count)",
"audio_nonzero_pcm=$(([regex]::Matches($all,'audio_out2\.port-nonzero-pcm')).Count)",
"audio_zero_pcm=$(([regex]::Matches($all,'audio_out2\.port-zero-pcm')).Count)",
"device_lost=$([int]$all.Contains('deviceLost=True'))"
)|Set-Content (Join-Path $out 'SUMMARY.txt') -Encoding UTF8
$zip="$out.zip";Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.24.1] RESULT: $zip"
