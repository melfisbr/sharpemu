$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.7.2-GFX10-MTBUF-D16-MIMG-ADAPTIVE-REBASE'

$AffectedFiles = @(
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs',
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs',
    'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
)

$RequiredV76051Hashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs' = '7dfa9c69563c068b4acaf9e48a6e714f16554b70ca141a55583e075851835fef'
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = '0783a960b89755ce5172598e01bf7d09c0fabdf0841654e4ea4ff572fc83b58f'
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs' = '1d569a968c456e04bd7eff3cc63f1ad7ef5029dc0af9fd725d75d3f85e7489a1'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs' = 'b733069d26919a08f99833af33cb64938a19e1319936e9a6ae7d0ddaeafe3b09'
}

$IndirectHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs'
$IndirectHelperHash = '2c395d530bffd6a9a998bda73210d13eb8de9fd1a2c75fe14a20486b2e3a5520'

$V76051TranslatorMarkers = @(
    'case "DsSwizzleB32"',
    'var usesDsSwizzle = false;',
    'usesDsSwizzle |= instruction.Opcode'
)

$V76061TranslatorMarkers = @(
    'IsIndirectPcTransferV7606(terminator.Opcode)',
    'IsIndirectPcTransferV7606(opcode);',
    'hasIndirectPcTransferV7606',
    'candidatePc == targetPc'
)

$V76061EvaluatorMarkers = @(
    'V76.0.6.1: follow statically-resolved S_SETPC/S_SWAPPC',
    'instruction.Opcode is "SLshlB64" or "SLshrB64" or "SAshrI64"'
)

$PatchSpecs = @(
    [pscustomobject]@{ Name='01_ir_buffer_control'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs'; Marker='TypedComponentCount = 0' },
    [pscustomobject]@{ Name='02_decode_mtbuf'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='TBufferLoadFormatD16Xyzw' },
    [pscustomobject]@{ Name='03_decode_mimg'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='ImageSampleCDO' },
    [pscustomobject]@{ Name='04_mtbuf_ir_decode'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='var componentCount = opcode switch' },
    [pscustomobject]@{ Name='05_vertex_binding_typed_format'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs'; Marker='if (control.TypedFormat is { } typedFormat)' },
    [pscustomobject]@{ Name='06_vertex_candidate_component_count'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs'; Marker='control.ComponentCount is >= 1 and <= 4' },
    [pscustomobject]@{ Name='07_typed_store_pending'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='typed-buffer store conversion pending' },
    [pscustomobject]@{ Name='08_typed_format_load'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='private uint NarrowGfx10FormatResultToD16(' },
    [pscustomobject]@{ Name='09_image_sample_parser_helper'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='private static bool TryDecodeImageSampleOpcodeV7607(' },
    [pscustomobject]@{ Name='10_vertex_fetch_d16'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='invalid MTBUF D16 vertex format=' },
    [pscustomobject]@{ Name='11_image_sample_modifier_decode'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='unsupported image sample modifier opcode=' }
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

function Assert-Prerequisites {
    param([string]$RepoRoot)

    foreach ($rel in $RequiredV76051Hashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        $expected = $RequiredV76051Hashes[$rel]
        if ($actual -ne $expected) {
            throw "V76.0.5.1 immutable prerequisite mismatch: $rel expected=$expected actual=$actual"
        }
    }

    $helperHash = Get-Sha256 (Join-Path $RepoRoot $IndirectHelperRel)
    if ($helperHash -ne $IndirectHelperHash) {
        throw "V76.0.6.1 helper mismatch: $IndirectHelperRel expected=$IndirectHelperHash actual=$helperHash"
    }

    $translator = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
    $evaluator = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs'
    if (-not (Test-FileContains $translator $V76051TranslatorMarkers)) {
        throw 'V76.0.5.1 translator markers ausentes.'
    }
    if (-not (Test-FileContains $translator $V76061TranslatorMarkers)) {
        throw 'V76.0.6.1 translator indirect-control markers ausentes.'
    }
    if (-not (Test-FileContains $evaluator $V76061EvaluatorMarkers)) {
        throw 'V76.0.6.1 scalar-evaluator markers ausentes.'
    }
    if (-not (Test-FileContains (Join-Path $RepoRoot $IndirectHelperRel) @('TryEmitIndirectPcTransferV7606','BitwiseAnd64(','SSwappcB64'))) {
        throw 'V76.0.6.1 indirect helper markers ausentes.'
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
        throw "Anchor semantica V76.0.7.2 invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count"
    }
    return [pscustomobject]@{ State='Ready'; Count=$count }
}

function Get-V76072State {
    param([string]$RepoRoot)
    Assert-Prerequisites $RepoRoot
    $ready = 0
    $applied = 0
    foreach ($spec in $PatchSpecs) {
        $result = Test-PatchSpec $RepoRoot $spec
        if ($result.State -eq 'Applied') { $applied++ } else { $ready++ }
    }
    if ($applied -eq $PatchSpecs.Count) { return 'AlreadyApplied' }
    return 'ReadyAdaptive'
}

function Assert-V76072Installed {
    param([string]$RepoRoot)
    Assert-Prerequisites $RepoRoot
    foreach ($spec in $PatchSpecs) {
        $target = Join-Path $RepoRoot $spec.Rel
        if (-not (Test-FileContains $target @($spec.Marker))) {
            throw "Marcador V76.0.7.2 ausente: $($spec.Name) / $($spec.Marker)"
        }
    }

    $ir = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs'
    $decoder = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
    $spirv = Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
    if (-not (Test-FileContains $ir @('TypedComponentCount','TypedFormat','public uint ComponentCount'))) {
        throw 'V76.0.7.2 IR final incompleto.'
    }
    if (-not (Test-FileContains $decoder @('TBufferLoadFormatD16X','TBufferStoreFormatD16Xyzw','ImageSampleCDO','ImageSampleCBO'))) {
        throw 'V76.0.7.2 decoder final incompleto.'
    }
    if (-not (Test-FileContains $spirv @('TryDecodeImageSampleOpcodeV7607','NarrowGfx10FormatResultToD16','typed-buffer store conversion pending','control.TypedFormat.HasValue'))) {
        throw 'V76.0.7.2 SPIR-V final incompleto.'
    }
}
