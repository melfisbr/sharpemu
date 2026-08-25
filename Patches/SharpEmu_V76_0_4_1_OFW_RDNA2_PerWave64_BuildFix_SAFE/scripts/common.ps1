$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Tag = "[V76.0.4.1-OFW-RDNA2-PER-WAVE64-BUILDFIX]"
$Repo = "C:\Users\Edpo\Documents\GitHub\sharpemu"
$Patches = Join-Path $Repo "Patches"
$TargetRel = "src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs"
$Target = Join-Path $Repo $TargetRel
$Payload = Join-Path $PSScriptRoot "..\payload\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs"
$ExpectedBrokenSha = "D6FEC976C9B559A8FCA3B8A3817EEB4283E194C4291D4E5B0156D56C18334462"
$ExpectedFixedSha = "CB0BA3A3C92D7DF6242E087C96612AE2D1C016A17ADAE46234AC4E938F032EBD"

function Get-FileSha([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Package {
    if (-not (Test-Path -LiteralPath $Payload -PathType Leaf)) { throw "$Tag payload ausente: $Payload" }
    $payloadSha = Get-FileSha $Payload
    if ($payloadSha -ne $ExpectedFixedSha) { throw "$Tag payload SHA256 divergente: $payloadSha" }
}

function Get-SourceState {
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { return "Missing" }
    $h = Get-FileSha $Target
    if ($h -eq $ExpectedBrokenSha) { return "V76.0.4-BrokenBuild" }
    if ($h -eq $ExpectedFixedSha) { return "V76.0.4.1-Applied" }
    return "Divergent:$h"
}
