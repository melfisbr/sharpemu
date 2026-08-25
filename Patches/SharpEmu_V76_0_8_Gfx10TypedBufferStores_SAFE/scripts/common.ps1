$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.8-GFX10-TYPED-BUFFER-STORES-D16'

$AffectedExistingFiles = @(
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
)
$HelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.TypedBufferStoreV7608.cs'
$HelperPayloadRel = 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.TypedBufferStoreV7608.cs'
$HelperHash = 'c35c29220a7d534ee77136d4183c557b70069071b314ffeed2fa735e813a73c3'

# Immutable pieces installed by V76.0.5.1. These remained unchanged through
# the validated V76.0.7.2 baseline and make a useful identity guard without
# hashing whole actively-developed shader files.
$RequiredV76051Hashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs' = '7dfa9c69563c068b4acaf9e48a6e714f16554b70ca141a55583e075851835fef'
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = '0783a960b89755ce5172598e01bf7d09c0fabdf0841654e4ea4ff572fc83b58f'
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs' = '1d569a968c456e04bd7eff3cc63f1ad7ef5029dc0af9fd725d75d3f85e7489a1'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs' = 'b733069d26919a08f99833af33cb64938a19e1319936e9a6ae7d0ddaeafe3b09'
}
$IndirectHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs'
$IndirectHelperHash = '2c395d530bffd6a9a998bda73210d13eb8de9fd1a2c75fe14a20486b2e3a5520'

$PatchSpecs = @(
    [pscustomobject]@{
        Name='01_mubuf_decode'
        Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
        Marker='V76.0.8 / GFX10 MUBUF: OP is eight bits'
    },
    [pscustomobject]@{
        Name='02_mubuf_ir'
        Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
        Marker='var formatD16 = opcode.Contains("FormatD16", StringComparison.Ordinal);'
    },
    [pscustomobject]@{
        Name='03_format_store_dispatch'
        Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
        Marker='EmitBufferFormatStoreV7608('
    },
    [pscustomobject]@{
        Name='04_d16_narrow_integer_kind'
        Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
        Marker='var isUint = Equal(numberFormat, 4);'
    }
)

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

function Read-NormalizedText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Arquivo ausente: $Path" }
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
}

function Test-FileContains {
    param([string]$Path, [string[]]$Markers)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($Path)
    foreach ($marker in $Markers) {
        if ($text.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) { return $false }
    }
    return $true
}

function Get-OccurrenceCount {
    param([string]$Text, [string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count = 0
    $start = 0
    while ($start -le $Text.Length - $Needle.Length) {
        $idx = $Text.IndexOf($Needle, $start, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) { break }
        $count++
        $start = $idx + $Needle.Length
    }
    return $count
}

function Get-PatchDataPath {
    param([string]$Name, [string]$Kind)
    return Join-Path $PackageRoot ("patchdata\{0}.{1}.txt" -f $Name, $Kind)
}

function Assert-V76072Base {
    param([string]$RepoRoot)

    foreach ($rel in $RequiredV76051Hashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        $expected = $RequiredV76051Hashes[$rel]
        if ($actual -ne $expected) {
            throw "V76.0.5.1 immutable prerequisite mismatch: $rel expected=$expected actual=$actual"
        }
    }

    $indirectActual = Get-Sha256 (Join-Path $RepoRoot $IndirectHelperRel)
    if ($indirectActual -ne $IndirectHelperHash) {
        throw "V76.0.6.1 indirect helper mismatch: expected=$IndirectHelperHash actual=$indirectActual"
    }

    $ir = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs'
    $decoder = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
    $evaluator = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs'
    $spirv = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'

    if (-not (Test-FileContains $ir @('TypedComponentCount = 0','TypedFormat = null','public uint ComponentCount'))) {
        throw 'V76.0.7.2 IR markers ausentes.'
    }
    if (-not (Test-FileContains $decoder @(
        'V76.0.7 / GFX10 MTBUF: OP is four bits',
        'TBufferLoadFormatD16Xyzw',
        'TBufferStoreFormatD16Xyzw',
        'ImageSampleCDO',
        'ImageSampleCBO'))) {
        throw 'V76.0.7.2 decoder markers ausentes.'
    }
    if (-not (Test-FileContains $evaluator @(
        'if (control.TypedFormat is { } typedFormat)',
        'control.ComponentCount is >= 1 and <= 4'))) {
        throw 'V76.0.7.2 scalar evaluator markers ausentes.'
    }
    if (-not (Test-FileContains $spirv @(
        'private uint NarrowGfx10FormatResultToD16(',
        'private static bool TryDecodeImageSampleOpcodeV7607(',
        'invalid MTBUF D16 vertex format=',
        'control.TypedFormat.HasValue'))) {
        throw 'V76.0.7.2 SPIR-V markers ausentes.'
    }
}

function Test-PatchSpec {
    param([string]$RepoRoot, $Spec)
    $target = Join-Path $RepoRoot $Spec.Rel
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "Arquivo alvo ausente: $($Spec.Rel)"
    }
    $text = Read-NormalizedText $target
    if ($text.IndexOf($Spec.Marker, [System.StringComparison]::Ordinal) -ge 0) {
        return [pscustomobject]@{ State='Applied'; Count=0 }
    }
    $old = Read-NormalizedText (Get-PatchDataPath $Spec.Name 'old')
    $count = Get-OccurrenceCount $text $old
    if ($count -ne 1) {
        throw "Anchor semantica V76.0.8 invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count"
    }
    return [pscustomobject]@{ State='Ready'; Count=$count }
}

function Get-HelperState {
    param([string]$RepoRoot)
    $path = Join-Path $RepoRoot $HelperRel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'Ready' }
    $actual = Get-Sha256 $path
    if ($actual -eq $HelperHash) { return 'Applied' }
    throw "Helper V76.0.8 divergente: $HelperRel expected=$HelperHash actual=$actual"
}

function Get-V7608State {
    param([string]$RepoRoot)
    Assert-V76072Base $RepoRoot
    $ready = 0
    $applied = 0
    foreach ($spec in $PatchSpecs) {
        $result = Test-PatchSpec $RepoRoot $spec
        if ($result.State -eq 'Applied') { $applied++ } else { $ready++ }
    }
    $helperState = Get-HelperState $RepoRoot
    if ($helperState -eq 'Applied') { $applied++ } else { $ready++ }
    if ($ready -eq 0) { return 'AlreadyApplied' }
    return 'ReadyAdaptive'
}

function Assert-V7608Installed {
    param([string]$RepoRoot)
    Assert-V76072Base $RepoRoot
    foreach ($spec in $PatchSpecs) {
        $target = Join-Path $RepoRoot $spec.Rel
        if (-not (Test-FileContains $target @($spec.Marker))) {
            throw "Marcador V76.0.8 ausente: $($spec.Name) / $($spec.Marker)"
        }
    }
    $helperActual = Get-Sha256 (Join-Path $RepoRoot $HelperRel)
    if ($helperActual -ne $HelperHash) {
        throw "Helper V76.0.8 hash mismatch: expected=$HelperHash actual=$helperActual"
    }

    $decoder = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
    $spirv = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
    $helper = Join-Path $RepoRoot $HelperRel
    if (-not (Test-FileContains $decoder @(
        'var opcode = (word >> 18) & 0xFF;',
        '0x80 => "BufferLoadFormatD16X"',
        '0x87 => "BufferStoreFormatD16Xyzw"',
        'formatD16',
        'componentCount'))) {
        throw 'V76.0.8 MUBUF D16 decode/IR final incompleto.'
    }
    if (-not (Test-FileContains $spirv @(
        'EmitBufferFormatStoreV7608(',
        'var isUint = Equal(numberFormat, 4);',
        'var isSint = Equal(numberFormat, 5);'))) {
        throw 'V76.0.8 SPIR-V dispatch/narrowing final incompleto.'
    }
    $spirvText = [System.IO.File]::ReadAllText($spirv)
    if ($spirvText.IndexOf('typed-buffer store conversion pending', [System.StringComparison]::Ordinal) -ge 0) {
        throw 'V76.0.8 ainda contem typed-buffer store pending.'
    }
    if (-not (Test-FileContains $helper @(
        'EmitBufferFormatStoreV7608',
        'LoadGfx10BufferFormatStoreSourceV7608',
        'ConvertGfx10BufferStoreComponentV7608',
        'EncodeUnsignedMiniFloatV7608',
        'StoreGuestBufferDwordV74054'))) {
        throw 'V76.0.8 typed-store helper incompleto.'
    }
}
