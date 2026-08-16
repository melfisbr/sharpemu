param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Split-Path -Parent $PSScriptRoot

$decoder = Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audio = Join-Path $root "src\SharpEmu.Libs\Media\BinkHostAudioBridgeV7241.cs"
$bootstrap = Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$cliProject = Join-Path $root "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
$runtimeTool = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$payload = Join-Path $packageRoot "payload\nihav-tool-native.exe"

foreach ($path in @($decoder,$audio,$bootstrap,$cliProject,$runtimeTool,$payload)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27.0.1] Required file missing: $path"
    }
}

$d = Read-Normalized -Path $decoder
$a = Read-Normalized -Path $audio
$b = Read-Normalized -Path $bootstrap
$c = Read-Normalized -Path $cliProject

foreach ($marker in @(
    "V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP",
    "V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR",
    "V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.27.0.1] V27 decoder marker missing: $marker"
    }
}

if (-not $a.Contains("V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO")) {
    throw "[V72.4.3.2.27.0.1] V27 audio marker missing."
}

if (-not $b.Contains("V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES")) {
    throw "[V72.4.3.2.27.0.1] V27 bootstrap marker missing."
}

$oldSource = '$(MSBuildProjectDirectory)\..\..\.sharpemu-tools\bink2\src\nihav\nihav-tool\target\release\nihav-tool.exe'
$newSource = '$(MSBuildProjectDirectory)\..\..\.sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe'

$hasOld = $c.Contains($oldSource)
$hasNew = $c.Contains($newSource)

if (-not $hasOld -and -not $hasNew) {
    throw "[V72.4.3.2.27.0.1] CLI NIHAV deploy source does not match known V61/V27 layouts."
}

if (-not $c.Contains('Target Name="CopySharpEmuNihavToolV6113166"')) {
    throw "[V72.4.3.2.27.0.1] CopySharpEmuNihavToolV6113166 target missing."
}

$runtimeHash = (Get-FileHash -LiteralPath $runtimeTool -Algorithm SHA256).Hash.ToLowerInvariant()
$payloadHash = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()

if ($payloadHash -ne "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18") {
    throw "[V72.4.3.2.27.0.1] Payload hash mismatch."
}

Write-Host "[V72.4.3.2.27.0.1] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.27.0.1] V27 source markers: PRESENT")
Write-Host ("[V72.4.3.2.27.0.1] Persistent CLI deploy already patched: " + $hasNew)
Write-Host ("[V72.4.3.2.27.0.1] Current runtime NIHAV SHA256: " + $runtimeHash)
Write-Host ("[V72.4.3.2.27.0.1] Required native NIHAV SHA256: " + $payloadHash)

if ($runtimeHash -ne $payloadHash) {
    Write-Host "[V72.4.3.2.27.0.1] CONFIRMED: runtime NIHAV is not the V27 native build and will be repaired." -ForegroundColor Yellow
}
