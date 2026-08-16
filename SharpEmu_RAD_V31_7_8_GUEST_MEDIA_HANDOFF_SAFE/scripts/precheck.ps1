param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$required = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs",
    "src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs",
    "src\SharpEmu.Libs\SharpEmu.Libs.csproj",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
)
foreach ($rel in $required) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.8] Required file missing: $path"
    }
}

$bridgePath = Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$bridge = [IO.File]::ReadAllText($bridgePath)
$span = Get-CSharpMethodSpanV3178 -Text $bridge -Signature "private static void TryStartConfiguredBootSequence()"
if ($span.Start -lt 0) {
    throw "[V72.4.3.2.31.7.8] TryStartConfiguredBootSequence() not found."
}

$method = $span.Text
foreach ($marker in @(
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "ps_studios_logo.bk2",
    "logo_intro.bk2",
    "bink2.auto_boot_order"
)) {
    if (-not $method.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] Unknown boot-method shape; missing '$marker'."
    }
}

$canonicalPath = Join-Path (Split-Path -Parent $PSScriptRoot) "patch\HostMovieBridge.TryStartConfiguredBootSequence.v3178.csfrag"
$canonical = [IO.File]::ReadAllText($canonicalPath).TrimEnd()
$methodState = "Unknown"
if ((Normalize-CSharpV3178 $method) -eq (Normalize-CSharpV3178 $canonical)) {
    $methodState = "Canonical"
}
elseif ($method.Contains("attract_movie.bk2") -or $bridge.Contains("bink2.ds_boot_attract_injected")) {
    $methodState = "AttractRegression"
}
else {
    throw "[V72.4.3.2.31.7.8] Boot method is neither canonical nor a recognized attract regression."
}

$rad = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs")
$api = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs")
$assist = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs")
foreach ($marker in @(
    "bink2.rad_attract_audio_anchor_pre_reveal",
    "sync_source=rad-playback-anchor-before-reveal",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath)",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(moviePath)"
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] V31.7.7/V31.7.6 RAD prerequisite missing: '$marker'."
    }
}
foreach ($marker in @(
    "bink2.rad_renderer_revealed",
    "bink2.rad_visual_cutoff",
    "SetParent"
)) {
    if (-not $api.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] Embedded RAD host prerequisite missing: '$marker'."
    }
}
foreach ($marker in @(
    "HostMovieExecutionGateV7243214.Begin()",
    "HostMovieExecutionGateV7243214.End()"
)) {
    if (-not $assist.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] Hard-gate prerequisite missing: '$marker'."
    }
}

$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.7.8] RAD REQUIRED: radvideo64.exe not found."
}
$radInfo = Get-Item -LiteralPath $radPath
$radHash = (Get-FileHash -LiteralPath $radPath -Algorithm SHA256).Hash

Write-Host "[V72.4.3.2.31.7.8] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31.7.8] BOOT_METHOD_STATE=" + $methodState)
Write-Host ("[V72.4.3.2.31.7.8] RAD_PLAYER=" + $radPath)
Write-Host ("[V72.4.3.2.31.7.8] RAD_VERSION=" + $radInfo.VersionInfo.FileVersion)
Write-Host ("[V72.4.3.2.31.7.8] RAD_SHA256=" + $radHash)
Write-Host "[V72.4.3.2.31.7.8] RAD/HARD_GATE=preserved; no decoder/resource-policy rewrite."
Write-Host "[V72.4.3.2.31.7.8] HOST_BOOT_BOUNDARY=ps_studios_logo -> logo_intro -> logo_intro_loop (if present)."
Write-Host "[V72.4.3.2.31.7.8] ATTRACT_OWNERSHIP=guest/EBOOT; host auto boot must not inject attract_movie."
Write-Host "[V72.4.3.2.31.7.8] AUDIO_EVIDENCE_PROBE=filtered guest I/O only for pr_demons_souls_intro; sidecar preserved until guest audio ownership is proven."
