$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.10.3-RDNA2-DS-SWIZZLE-B32-ADAPTIVE-REBASE'
$MainRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
$HelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.DsSwizzleV7610.cs'
$MainBeforeHash = '5e6492f18bf7ec3042c47dc05d6f097cffae512a96f9f4fb405d99b248e8802a'
$MainAfterHash = '81f81c1d897afbd03e86c6ad2223a6b3e742c57009a363df9ee6657e4f3f89b5'
$HelperAfterHash = '99e575ffd9eab1e275dfa3ad548c5ec994a5f8e1172dfb693270ae4d808a81c1'
$PrerequisiteHashes = @{
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs' = 'e4dfd261652d4130c3e42ce9f030dc4bb4c5bf00a87f18dc5d1fcc3fd6043453'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs' = 'addd358c37ec7393bfeaaa9b0fa124236b5224d8fe0bb8d233cd3db52707b598'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs' = '27e22e6afdcd945e84824405e3d08591ea165e0130d648a7582e00f721959bbd'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.TypedBufferStoreV7608.cs' = 'c35c29220a7d534ee77136d4183c557b70069071b314ffeed2fa735e813a73c3'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.AtomicCompatV7609.cs' = '4456dafc25323127bf996dccd5b943eb2298282612b0cc1681db2e0078e6cf4d'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs' = '2c395d530bffd6a9a998bda73210d13eb8de9fd1a2c75fe14a20486b2e3a5520'
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = 'f1cff905d31904a870105aba7ae250f796089cd706a21a5f7a7da2d74f2354fe'
    'src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.cs' = '9f233bce24ccdb1afee6f35be96c3e22f1f4d942ddebd6033e93f69084fbbcef'
}

function Get-RepoRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) { $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu' }
    $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    $probe = Join-Path $resolved 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "Repo root invalido: $resolved" }
    return $resolved
}
function Get-PatchesRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) { $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches' }
    if (-not (Test-Path -LiteralPath $RequestedRoot -PathType Container)) { New-Item -ItemType Directory -Path $RequestedRoot -Force | Out-Null }
    return [System.IO.Path]::GetFullPath($RequestedRoot)
}
function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-Prerequisites {
    param([string]$RepoRoot)
    foreach ($rel in $PrerequisiteHashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        $expected = $PrerequisiteHashes[$rel]
        if ($actual -ne $expected) { throw "Prerequisite divergente: $rel expected=$expected actual=$actual" }
    }
    $mainText=[System.IO.File]::ReadAllText((Join-Path $RepoRoot $MainRel))
    foreach ($marker in @('"SClause" or','"SWaitcntDepctr" or','DeclareRdnaAtomicCompatV7609();')) {
        if ($mainText.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0) { throw "Baseline V76.0.10.2 marker ausente: $marker" }
    }
}
function Get-PackageState {
    param([string]$RepoRoot)
    Assert-Prerequisites $RepoRoot
    $main = Get-Sha256 (Join-Path $RepoRoot $MainRel)
    $helperPath = Join-Path $RepoRoot $HelperRel
    $helperExists = Test-Path -LiteralPath $helperPath -PathType Leaf
    $helperHash = if ($helperExists) { Get-Sha256 $helperPath } else { $null }
    if ($main -eq $MainBeforeHash -and -not $helperExists) { return 'Ready' }
    if ($main -eq $MainAfterHash -and $helperHash -eq $HelperAfterHash) { return 'AlreadyApplied' }
    throw "Source divergente: main=$main helper=$helperHash helper_exists=$helperExists"
}
function Assert-Installed {
    param([string]$RepoRoot)
    Assert-Prerequisites $RepoRoot
    $main = Get-Sha256 (Join-Path $RepoRoot $MainRel)
    $helper = Get-Sha256 (Join-Path $RepoRoot $HelperRel)
    if ($main -ne $MainAfterHash) { throw "Main hash final invalido expected=$MainAfterHash actual=$main" }
    if ($helper -ne $HelperAfterHash) { throw "Helper hash final invalido expected=$HelperAfterHash actual=$helper" }
    $mainText=[System.IO.File]::ReadAllText((Join-Path $RepoRoot $MainRel))
    $helperText=[System.IO.File]::ReadAllText((Join-Path $RepoRoot $HelperRel))
    foreach ($marker in @('TryEmitDsSwizzleB32V7610','instruction.Opcode != "DsSwizzleB32"','"SClause" or','"SWaitcntDepctr" or')) {
        if ($mainText.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0) { throw "Marcador final ausente no main: $marker" }
    }
    foreach ($marker in @('FFT mode from the RDNA2 ISA','Rotate mode from the RDNA2 ISA','GroupNonUniformShuffle','PopCount5V7610')) {
        if ($helperText.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0) { throw "Marcador final ausente no helper: $marker" }
    }
}
