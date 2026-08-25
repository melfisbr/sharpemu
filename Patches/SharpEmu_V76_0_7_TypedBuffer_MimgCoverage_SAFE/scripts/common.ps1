$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.7-GFX10-MTBUF-D16-MIMG-COVERAGE'

$AffectedFiles = @(
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs',
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs',
    'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
)

$BaselineHashes = @{
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs' = '533eea0914bd430fcb859e8677a612fe597e4e86a6e4ed90ad379996920c71cc'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs' = '8c8943c3de5d79a0cb9db32ab98753a28234d5ec37ba2070f60af64c5111d7a4'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs' = 'a3d475e18ca3a866bbb086275fc19b874750456690d887826ffae6e3774e0f3d'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs' = '2d776a99fe5c2e9d49b454afac3243d803cf2c7c72b681c2c94b44520e9326f3'
}

$PayloadHashes = @{
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs' = 'addd358c37ec7393bfeaaa9b0fa124236b5224d8fe0bb8d233cd3db52707b598'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs' = 'e780ee22432ccde397ac42d12e4dfcf0e3e7cf95e3ecc78fb9ed0c7e50f51dd4'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs' = '27e22e6afdcd945e84824405e3d08591ea165e0130d648a7582e00f721959bbd'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs' = 'e13edcb3429355a5fa16eb15d73ab2083e532614c9c01da06bc9ec366bf944d4'
}

$IndirectHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs'
$IndirectHelperHash = '353c91c09c3f2bf69ec166160f30e50a6cd33db74cbbb05aa4343f9d2ac41664'

function Get-RepoRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
    }
    $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    $probe = Join-Path $resolved 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
        throw "Repo root invalido: $resolved (faltando $probe)"
    }
    return $resolved
}

function Get-PatchesRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
    }
    if (-not (Test-Path -LiteralPath $RequestedRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $RequestedRoot -Force | Out-Null
    }
    return [System.IO.Path]::GetFullPath($RequestedRoot)
}

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-FileContains {
    param([string]$Path, [string[]]$Markers)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($Path)
    foreach ($marker in $Markers) {
        if ($text.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            return $false
        }
    }
    return $true
}

function Assert-V76061Baseline {
    param([string]$RepoRoot)
    $helper = Join-Path $RepoRoot $IndirectHelperRel
    $helperHash = Get-Sha256 $helper
    if ($helperHash -ne $IndirectHelperHash) {
        throw "V76.0.6.1 prerequisite mismatch: $IndirectHelperRel expected=$IndirectHelperHash actual=$helperHash"
    }
    if (-not (Test-FileContains $helper @('TryEmitIndirectPcTransferV7606', 'SSwappcB64'))) {
        throw 'V76.0.6.1 indirect-control markers ausentes.'
    }
}

function Get-V7607State {
    param([string]$RepoRoot)
    Assert-V76061Baseline $RepoRoot
    $baselineCount = 0
    $payloadCount = 0
    foreach ($rel in $AffectedFiles) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        if ($actual -eq $BaselineHashes[$rel]) { $baselineCount++ }
        if ($actual -eq $PayloadHashes[$rel]) { $payloadCount++ }
    }
    if ($payloadCount -eq $AffectedFiles.Count) { return 'AlreadyApplied' }
    if ($baselineCount -eq $AffectedFiles.Count) { return 'Ready' }
    return 'Divergent'
}

function Assert-V7607Installed {
    param([string]$RepoRoot)
    Assert-V76061Baseline $RepoRoot
    foreach ($rel in $AffectedFiles) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        $expected = $PayloadHashes[$rel]
        if ($actual -ne $expected) {
            throw "V76.0.7 payload hash mismatch: $rel expected=$expected actual=$actual"
        }
    }
    $decoder = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
    $ir = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs'
    $spirv = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
    if (-not (Test-FileContains $decoder @(
        'TBufferLoadFormatD16X',
        'TBufferStoreFormatD16Xyzw',
        'ImageSampleCDO',
        'ImageSampleCBO'
    ))) { throw 'V76.0.7 decoder markers incompletos.' }
    if (-not (Test-FileContains $ir @('TypedComponentCount', 'TypedFormat', 'public uint ComponentCount'))) {
        throw 'V76.0.7 IR markers incompletos.'
    }
    if (-not (Test-FileContains $spirv @(
        'TryDecodeImageSampleOpcodeV7607',
        'NarrowGfx10FormatResultToD16',
        'typed-buffer store conversion pending',
        'control.TypedFormat.HasValue'
    ))) { throw 'V76.0.7 SPIR-V markers incompletos.' }
}
