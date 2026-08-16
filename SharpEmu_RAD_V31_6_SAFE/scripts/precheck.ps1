param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$required = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "src\SharpEmu.Libs\SharpEmu.Libs.csproj",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
)

foreach ($rel in $required) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.6] Required file missing: $path"
    }
}

$hostText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs")
$audioText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs")
$bootstrapText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs")

foreach ($marker in @(
    "RAD_EXTERNAL_BACKEND",
    "MovieMode.Rad",
    "AttachRadMovieLocked",
    "Bink RAD bridge attached",
    "Bink RAD bridge completed"
)) {
    if (-not $hostText.Contains($marker)) {
        throw "[V72.4.3.2.31.6] V31.4 RAD host integration is not installed: missing '$marker'."
    }
}

foreach ($marker in @(
    "BinkDemonSoulsIntroAudioV7243227",
    "pr_demons_souls_intro_music.at9",
    "pr_demons_souls_intro_sfx.at9",
    "pr_demons_souls_intro_vo.at9",
    "AttractOffsetSeconds"
)) {
    if (-not $audioText.Contains($marker)) {
        throw "[V72.4.3.2.31.6] Demon's Souls intro-audio prerequisite missing: '$marker'."
    }
}

if (-not $bootstrapText.Contains('SetDefault("SHARPEMU_BINK_MODE", "rad");')) {
    throw "[V72.4.3.2.31.6] RAD default is not installed in BinkRuntimeBootstrapV6113166.cs."
}

$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
$report = Write-RadDiscoveryReport -RepositoryRoot $root -RadPath $radPath

if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.6] RAD REQUIRED: radvideo64.exe not found. Discovery report: $report"
}

$ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    $localFfmpeg = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\ffmpeg.exe"
    if (Test-Path -LiteralPath $localFfmpeg -PathType Leaf) {
        $ffmpegPath = $localFfmpeg
    }
    else {
        throw "[V72.4.3.2.31.6] ffmpeg.exe is required to build the external attract audio stems."
    }
}
else {
    $ffmpegPath = $ffmpeg.Source
}

function Read-BinkAudioHeader {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Path=$Path; Known=$false; Tag=""; Tracks=-1; Ids=@() }
    }

    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.BinaryReader($stream,[Text.Encoding]::ASCII,$true)
        try {
            if ($stream.Length -lt 48) {
                return [pscustomobject]@{ Path=$Path; Known=$false; Tag=""; Tracks=-1; Ids=@() }
            }

            $tag = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $isBink1 = $tag.StartsWith("BIK",[StringComparison]::Ordinal)
            $isBink2 = $tag.StartsWith("KB2",[StringComparison]::Ordinal)
            if (-not $isBink1 -and -not $isBink2) {
                return [pscustomobject]@{ Path=$Path; Known=$false; Tag=$tag; Tracks=-1; Ids=@() }
            }

            $stream.Position = 40
            $count = [uint32]$reader.ReadUInt32()
            if ($count -gt 256) {
                return [pscustomobject]@{ Path=$Path; Known=$false; Tag=$tag; Tracks=-1; Ids=@() }
            }

            $revision = $tag.Substring(3,1)
            $hasNewField =
                ($isBink1 -and $revision -eq "k") -or
                ($isBink2 -and $revision -in @("i","j","k"))
            if ($hasNewField) {
                [void]$reader.ReadUInt32()
            }

            $stream.Position += [int64]$count * 4
            $stream.Position += [int64]$count * 4

            $ids = @()
            for ($i=0; $i -lt $count; $i++) {
                $ids += [uint32]$reader.ReadUInt32()
            }

            return [pscustomobject]@{
                Path=$Path
                Known=$true
                Tag=$tag
                Tracks=[int]$count
                Ids=$ids
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$movies = Join-Path (Split-Path -Parent "F:\JOGOSPS5\PPSA01341\eboot.bin") "movies"
$headers = @()
foreach ($name in @("ps_studios_logo.bk2","logo_intro.bk2","attract_movie.bk2")) {
    $headers += Read-BinkAudioHeader -Path (Join-Path $movies $name)
}

$version = (Get-Item -LiteralPath $radPath).VersionInfo.FileVersion
$hash = (Get-FileHash -LiteralPath $radPath -Algorithm SHA256).Hash

Write-Host "[V72.4.3.2.31.6] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31.6] RAD_PLAYER=" + $radPath)
Write-Host ("[V72.4.3.2.31.6] RAD_VERSION=" + $version)
Write-Host ("[V72.4.3.2.31.6] RAD_SHA256=" + $hash)
Write-Host ("[V72.4.3.2.31.6] FFMPEG=" + $ffmpegPath)

foreach ($header in $headers) {
    $idText = if ($header.Ids.Count -gt 0) { $header.Ids -join ";" } else { "" }
    Write-Host (
        "[V72.4.3.2.31.6] BINK_AUDIO_HEADER file=" +
        [IO.Path]::GetFileName($header.Path) +
        " tag=" + $header.Tag +
        " known=" + $header.Known +
        " tracks=" + $header.Tracks +
        " ids=" + $idText)
}

$attract = $headers | Where-Object { [IO.Path]::GetFileName($_.Path) -ieq "attract_movie.bk2" } | Select-Object -First 1
if ($null -ne $attract -and $attract.Known -and $attract.Tracks -eq 0) {
    Write-Host "[V72.4.3.2.31.6] ATTRACT AUDIO DIAGNOSIS CONFIRMED: BK2 has zero embedded audio tracks; external AT9 opening stems will be used at 1.0000 tempo." -ForegroundColor Green
}
elseif ($null -ne $attract -and $attract.Known) {
    Write-Host "[V72.4.3.2.31.6] attract_movie contains embedded audio; RAD will retain ownership and no sidecar will be started." -ForegroundColor Yellow
}
else {
    Write-Host "[V72.4.3.2.31.6] attract_movie audio header could not be read; safe policy is RAD-only (no guessed sidecar)." -ForegroundColor Yellow
}

Write-Host ("[V72.4.3.2.31.6] Discovery report: " + $report)
