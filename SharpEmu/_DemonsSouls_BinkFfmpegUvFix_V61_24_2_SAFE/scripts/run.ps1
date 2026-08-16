param([string]$RepositoryRoot,[string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
$t=Join-Path $r 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
if([IO.File]::ReadAllText($t).IndexOf('V61.24.2 FFMPEG_UV_SWAP',[StringComparison]::Ordinal)-lt 0){
    throw 'DIAGNOSTIC ERROR: run APPLY_BUILD V61.24.2 first.'
}
$exe=Join-Path $r 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $r "SharpEmu_V61_24_2_BINK_COLOR_$stamp";New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out 'stdout.log';$stderr=Join-Path $out 'stderr.log'

# Preserve proven full-frame playback.
$env:SHARPEMU_BINK_REALTIME_DEADLINE='0'
# Use persistent FFmpeg conversion, but now explicitly swap its U/V planes.
$env:SHARPEMU_BINK_FFMPEG_COLOR='1'
$env:SHARPEMU_BINK_FFMPEG_UV_SWAP='1'
$env:SHARPEMU_NIHAV_UV_SWAP='0'
$env:SHARPEMU_NIHAV_AUTO_RANGE='1'
$env:SHARPEMU_LOG_BINK2='1'

# AJM trace was extremely high-volume in V61.24.1; the result already proved
# initialization/module/batches are reached but no decoder instance is created.
$env:SHARPEMU_LOG_AJM=$null
$env:SHARPEMU_LOG_AUDIO=$null
$env:SHARPEMU_LOG_AUDIOOUT=$null
$env:SHARPEMU_LOG_AUDIOOUT2=$null
$env:SHARPEMU_LOG_AGC=$null
$env:SHARPEMU_LOG_AGC_SHADER=$null
$env:SHARPEMU_LOG_VK_RESOURCES=$null

Write-Host '[V61.24.2] Full Bink playback retained.'
Write-Host '[V61.24.2] FFmpeg U/V swap ENABLED at the actual swscale input.'
Write-Host '[V61.24.2] Observe PlayStation Studios and logo colors, then close SharpEmu.'

$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
$all=''
if(Test-Path $stdout){$all+=[IO.File]::ReadAllText($stdout)}
if(Test-Path $stderr){$all+="`n"+[IO.File]::ReadAllText($stderr)}
($all -split "`r?`n"|Select-String -Pattern 'bink2\.|Bink2 bridge|ffmpeg|color|range|uv_swap|deviceLost'|ForEach-Object{$_.Line})|Set-Content (Join-Path $out 'FOCUS.txt') -Encoding UTF8
@(
'version=61.24.2',
"exit_code=$($p.ExitCode)",
"ps_logo_complete=$([int]($all -match 'Bink2 bridge completed: ps_studios_logo\.bk2[^\r\n]*frame 254'))",
"ffmpeg_color_ready=$(([regex]::Matches($all,'bink2\.ffmpeg_color_ready')).Count)",
"ffmpeg_fallback=$(([regex]::Matches($all,'bink2\.ffmpeg_color_fallback')).Count)",
"device_lost=$([int]$all.Contains('deviceLost=True'))"
)|Set-Content (Join-Path $out 'SUMMARY.txt') -Encoding UTF8
$zip="$out.zip";Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.24.2] RESULT: $zip"
