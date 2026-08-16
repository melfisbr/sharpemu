param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$GameRoot="F:\JOGOSPS5\PPSA01341")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$game = (Resolve-Path -LiteralPath $GameRoot).Path

$music = Join-Path $game "sound\streams\07_cutscene_music\pr_demons_souls_intro_music.at9"
$sfx   = Join-Path $game "sound\streams\05_cutscene_sfx\pr_demons_souls_intro_sfx.at9"
$vo    = Join-Path $game "sound\streams\06_cutscene_vo\en\pr_demons_souls_intro_vo.at9"

foreach ($path in @($music,$sfx,$vo)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.5] Required Demon's Souls opening audio stem missing: $path"
    }
}

$ffmpegPath = $env:SHARPEMU_FFMPEG
if ([string]::IsNullOrWhiteSpace($ffmpegPath) -or
    -not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf))
{
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        $ffmpegPath = $cmd.Source
    }
    else {
        $local = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\ffmpeg.exe"
        if (Test-Path -LiteralPath $local -PathType Leaf) {
            $ffmpegPath = $local
        }
        else {
            throw "[V72.4.3.2.31.7.5] ffmpeg.exe not found for attract audio cache prewarm."
        }
    }
}

function Test-Wave {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $info = Get-Item -LiteralPath $Path
    if ($info.Length -le 44) { return $false }

    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $buffer = New-Object byte[] 12
        if ($stream.Read($buffer,0,12) -ne 12) { return $false }
        $riff = [Text.Encoding]::ASCII.GetString($buffer,0,4)
        $wave = [Text.Encoding]::ASCII.GetString($buffer,8,4)
        return $riff -eq "RIFF" -and $wave -eq "WAVE"
    }
    finally {
        $stream.Dispose()
    }
}

$builder = New-Object Text.StringBuilder
foreach ($path in @($music,$sfx,$vo)) {
    $info = Get-Item -LiteralPath $path
    [void]$builder.Append($path)
    [void]$builder.Append('|')
    [void]$builder.Append($info.Length)
    [void]$builder.Append('|')
    [void]$builder.Append($info.LastWriteTimeUtc.Ticks)
    [void]$builder.Append(';')
}

$sha = [Security.Cryptography.SHA256]::Create()
try {
    $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString()))
}
finally {
    $sha.Dispose()
}
$key = ([BitConverter]::ToString($digest,0,8)).Replace('-','').ToLowerInvariant()

$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) {
    $localData = [IO.Path]::GetTempPath()
}
$cache = Join-Path $localData "SharpEmu\MediaCache\DemonSouls"
New-Item -ItemType Directory -Force -Path $cache | Out-Null

$full = Join-Path $cache ("demons-souls-intro-" + $key + ".wav")
$tail = Join-Path $cache ("demons-souls-intro-" + $key + "-from12-v29-1p000.wav")

$tmp = $full + ".tmp-" + [Guid]::NewGuid().ToString("N") + ".wav"
try {
    Write-Host "[V72.4.3.2.31.7.5] Rebuilding full Demon's Souls opening mix from original AT9 stems at native rate..."
    $args = @(
        "-hide_banner","-loglevel","error","-nostdin","-y",
        "-i",$music,
        "-i",$sfx,
        "-i",$vo,
        "-filter_complex",
        "[0:a]aformat=sample_rates=48000:channel_layouts=stereo[m];[1:a]aformat=sample_rates=48000:channel_layouts=stereo[s];[2:a]aformat=sample_rates=48000:channel_layouts=stereo[v];[m][s][v]amix=inputs=3:duration=longest:dropout_transition=0:normalize=1[out]",
        "-map","[out]",
        "-c:a","pcm_s16le","-ar","48000","-ac","2",
        $tmp)
    & $ffmpegPath @args
    if ($LASTEXITCODE -ne 0 -or -not (Test-Wave -Path $tmp)) {
        throw "[V72.4.3.2.31.7.5] ffmpeg failed to create the full opening mix."
    }
    Move-Item -LiteralPath $tmp -Destination $full -Force
}
finally {
    if (Test-Path -LiteralPath $tmp -PathType Leaf) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

$tmp = $tail + ".tmp-" + [Guid]::NewGuid().ToString("N") + ".wav"
try {
    Write-Host "[V72.4.3.2.31.7.5] Rebuilding exact runtime attract +12.000 s / 1.0000x audio tail..."
    $args = @(
        "-hide_banner","-loglevel","error","-nostdin","-y",
        "-ss","12.000",
        "-i",$full,
        "-filter:a","atempo=1.0000",
        "-c:a","pcm_s16le","-ar","48000","-ac","2",
        $tmp)
    & $ffmpegPath @args
    if ($LASTEXITCODE -ne 0 -or -not (Test-Wave -Path $tmp)) {
        throw "[V72.4.3.2.31.7.5] ffmpeg failed to create the native-rate attract audio tail."
    }
    Move-Item -LiteralPath $tmp -Destination $tail -Force
}
finally {
    if (Test-Path -LiteralPath $tmp -PathType Leaf) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

$tailInfo = Get-Item -LiteralPath $tail
Write-Host ("[V72.4.3.2.31.7.5] ATTRACT_AUDIO_RUNTIME_CACHE_BYTES=" + $tailInfo.Length)

Write-Host ("[V72.4.3.2.31.7.5] ATTRACT_AUDIO_CACHE=" + $tail)
Write-Host "[V72.4.3.2.31.7.5] ATTRACT AUDIO CACHE PREWARM PASSED." -ForegroundColor Green
