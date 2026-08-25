$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.10.4.1-RDNA2-DPP-PERMLANE-ADAPTIVE-CACHE-REBASE'
$AluRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs'
$CacheRel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'

$AluBeforeHash = 'ea8df89cb52ee9892a00a14f06d3a965bf0518781674af83940f0e0cadb009e8'
$AluAfterHash  = '2ff2b1358d273c07ae1fa09f37977555d189f343a38c381c324e2d0c7592330a'
$CacheBeforeHash = '09b7daedf5eab60c1979012d6cf125c9a607623e8df5072f6d487c9907ccbbd3'
$CacheVersionAfter = 'V76.0.10.4-r1'

$PrerequisiteHashes = @{
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs' = '81f81c1d897afbd03e86c6ad2223a6b3e742c57009a363df9ee6657e4f3f89b5'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.DsSwizzleV7610.cs' = '99e575ffd9eab1e275dfa3ad548c5ec994a5f8e1172dfb693270ae4d808a81c1'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs' = 'e4dfd261652d4130c3e42ce9f030dc4bb4c5bf00a87f18dc5d1fcc3fd6043453'
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs' = 'addd358c37ec7393bfeaaa9b0fa124236b5224d8fe0bb8d233cd3db52707b598'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.TypedBufferStoreV7608.cs' = 'c35c29220a7d534ee77136d4183c557b70069071b314ffeed2fa735e813a73c3'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.AtomicCompatV7609.cs' = '4456dafc25323127bf996dccd5b943eb2298282612b0cc1681db2e0078e6cf4d'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs' = '2c395d530bffd6a9a998bda73210d13eb8de9fd1a2c75fe14a20486b2e3a5520'
}

function Get-RepoRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
    }
    $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    $probe = Join-Path $resolved 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
        throw "Repo root invalido: $resolved"
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

function Assert-Prerequisites {
    param([string]$RepoRoot)
    foreach ($rel in $PrerequisiteHashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        $expected = $PrerequisiteHashes[$rel]
        if ($actual -ne $expected) {
            throw "Prerequisite divergente: $rel expected=$expected actual=$actual"
        }
    }

    $mainText = [System.IO.File]::ReadAllText(
        (Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'))
    foreach ($marker in @(
        'TryEmitDsSwizzleB32V7610',
        '"SClause" or',
        '"SWaitcntDepctr" or',
        'DeclareRdnaAtomicCompatV7609();')) {
        if ($mainText.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Baseline V76.0.10.3 marker ausente: $marker"
        }
    }
}

function Test-CacheVersionInstalled {
    param([string]$CachePath)
    if (-not (Test-Path -LiteralPath $CachePath -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($CachePath)
    $marker = 'private const string CacheVersion = "' + $CacheVersionAfter + '";'
    return $text.IndexOf($marker, [System.StringComparison]::Ordinal) -ge 0
}

function Get-PackageState {
    param([string]$RepoRoot)
    Assert-Prerequisites $RepoRoot
    $aluPath = Join-Path $RepoRoot $AluRel
    $cachePath = Join-Path $RepoRoot $CacheRel
    $alu = Get-Sha256 $aluPath
    $cache = Get-Sha256 $cachePath

    if ($alu -eq $AluBeforeHash -and $cache -eq $CacheBeforeHash) {
        return 'Ready'
    }
    if ($alu -eq $AluAfterHash -and (Test-CacheVersionInstalled $cachePath)) {
        return 'AlreadyApplied'
    }
    throw "Source divergente: alu=$alu cache=$cache cache_version_target=$(Test-CacheVersionInstalled $cachePath)"
}

function Set-CacheVersionAdaptive {
    param([string]$CachePath)

    $beforeHash = Get-Sha256 $CachePath
    if ($beforeHash -ne $CacheBeforeHash) {
        throw "Cache mudou antes do patch: expected=$CacheBeforeHash actual=$beforeHash"
    }

    $bytes = [System.IO.File]::ReadAllBytes($CachePath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [System.IO.File]::ReadAllText($CachePath)

    $pattern = 'private const string CacheVersion\s*=\s*"[^"]+";'
    $cacheVersionMatches = [System.Text.RegularExpressions.Regex]::Matches($text, $pattern)
    if ($cacheVersionMatches.Count -ne 1) {
        throw "CacheVersion estrutural invalido: matches=$($cacheVersionMatches.Count)"
    }

    $replacement = 'private const string CacheVersion = "' + $CacheVersionAfter + '";'
    $patched = [System.Text.RegularExpressions.Regex]::Replace($text, $pattern, $replacement, 1)
    if ($patched -eq $text) {
        throw 'CacheVersion nao foi alterado'
    }

    $encoding = [System.Text.UTF8Encoding]::new($hasBom)
    [System.IO.File]::WriteAllText($CachePath, $patched, $encoding)

    if (-not (Test-CacheVersionInstalled $CachePath)) {
        throw 'CacheVersion final nao foi instalado'
    }
}

function Assert-Installed {
    param([string]$RepoRoot)
    Assert-Prerequisites $RepoRoot

    $aluPath = Join-Path $RepoRoot $AluRel
    $cachePath = Join-Path $RepoRoot $CacheRel
    $alu = Get-Sha256 $aluPath
    if ($alu -ne $AluAfterHash) {
        throw "ALU hash final invalido expected=$AluAfterHash actual=$alu"
    }
    if (-not (Test-CacheVersionInstalled $cachePath)) {
        throw "CacheVersion final invalido expected=$CacheVersionAfter"
    }

    $aluText = [System.IO.File]::ReadAllText($aluPath)
    foreach ($marker in @(
        'GFX10 PERMLANE overloads OP_SEL[0:1]',
        'var boundControl = (control.OperandSelect & 2) != 0',
        'DPP_BOUND_OFF + FI=0',
        'sourceAllowsWrite = _module.AddInstruction')) {
        if ($aluText.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Marcador ALU final ausente: $marker"
        }
    }
}
