param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$required = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "src\SharpEmu.Libs\SharpEmu.Libs.csproj",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
)

foreach ($rel in $required) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.5] Required file missing: $path"
    }
}

$hostText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs")
$bootstrapText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs")

foreach ($marker in @(
    "RAD_EXTERNAL_BACKEND",
    "MovieMode.Rad",
    "AttachRadMovieLocked",
    "Bink RAD bridge attached",
    "Bink RAD bridge completed"
)) {
    if (-not $hostText.Contains($marker)) {
        throw "[V72.4.3.2.31.5] V31.4 RAD host integration is not installed: missing '$marker'."
    }
}

if (-not $bootstrapText.Contains('SetDefault("SHARPEMU_BINK_MODE", "rad");')) {
    throw "[V72.4.3.2.31.5] RAD default is not installed in BinkRuntimeBootstrapV6113166.cs."
}

$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
$report = Write-RadDiscoveryReport -RepositoryRoot $root -RadPath $radPath

if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.5] RAD REQUIRED: radvideo64.exe not found. Discovery report: $report"
}

$version = (Get-Item -LiteralPath $radPath).VersionInfo.FileVersion
$hash = (Get-FileHash -LiteralPath $radPath -Algorithm SHA256).Hash

Write-Host "[V72.4.3.2.31.5] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31.5] RAD_PLAYER=" + $radPath)
Write-Host ("[V72.4.3.2.31.5] RAD_VERSION=" + $version)
Write-Host ("[V72.4.3.2.31.5] RAD_SHA256=" + $hash)
Write-Host "[V72.4.3.2.31.5] V31.4 in-process SharpEmu host hooks are present."
Write-Host "[V72.4.3.2.31.5] Repair target: remove invalid BinkPlay '/#' argument; preserve RAD-only policy."
Write-Host ("[V72.4.3.2.31.5] Discovery report: " + $report)
