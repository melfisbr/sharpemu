$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.6.1-GEN5-INDIRECT-SHADER-CONTROL-BUILDFIX'

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

$TranslatorRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
$EvaluatorRel = 'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs'
$IndirectHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs'
$BackendRel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs'

$RequiredV76051Hashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs' = '7dfa9c69563c068b4acaf9e48a6e714f16554b70ca141a55583e075851835fef'
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = '0783a960b89755ce5172598e01bf7d09c0fabdf0841654e4ea4ff572fc83b58f'
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs' = '1d569a968c456e04bd7eff3cc63f1ad7ef5029dc0af9fd725d75d3f85e7489a1'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs' = 'b733069d26919a08f99833af33cb64938a19e1319936e9a6ae7d0ddaeafe3b09'
}

$V76051TranslatorMarkers = @(
    'case "DsSwizzleB32"',
    'var usesDsSwizzle = false;',
    'usesDsSwizzle |= instruction.Opcode'
)

$V7606TranslatorMarkers = @(
    'IsIndirectPcTransferV7606(terminator.Opcode)',
    'IsIndirectPcTransferV7606(opcode);',
    'hasIndirectPcTransferV7606',
    'candidatePc == targetPc'
)

$V7606EvaluatorMarkers = @(
    'V76.0.6.1: follow statically-resolved S_SETPC/S_SWAPPC',
    'instruction.Opcode is "SLshlB64" or "SLshrB64" or "SAshrI64"'
)

function Assert-V76051Installed {
    param([string]$RepoRoot)
    foreach ($rel in $RequiredV76051Hashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        $expected = $RequiredV76051Hashes[$rel]
        if ($actual -ne $expected) {
            throw "V76.0.5.1 prerequisite mismatch: $rel expected=$expected actual=$actual"
        }
    }
    if (-not (Test-FileContains (Join-Path $RepoRoot $TranslatorRel) $V76051TranslatorMarkers)) {
        throw 'V76.0.5.1 translator markers ausentes.'
    }
}

function Get-V7606State {
    param([string]$RepoRoot)
    Assert-V76051Installed $RepoRoot

    $translator = Join-Path $RepoRoot $TranslatorRel
    $evaluator = Join-Path $RepoRoot $EvaluatorRel
    if (-not (Test-Path -LiteralPath $translator -PathType Leaf)) { throw "Ausente: $TranslatorRel" }
    if (-not (Test-Path -LiteralPath $evaluator -PathType Leaf)) { throw "Ausente: $EvaluatorRel" }

    $helper = Join-Path $RepoRoot $IndirectHelperRel
    $translatorApplied = Test-FileContains $translator $V7606TranslatorMarkers
    $evaluatorApplied = Test-FileContains $evaluator $V7606EvaluatorMarkers
    $helperApplied = Test-FileContains $helper @('TryEmitIndirectPcTransferV7606', 'SSwappcB64')

    if ($translatorApplied -and $evaluatorApplied -and $helperApplied) {
        return 'AlreadyApplied'
    }
    if ($translatorApplied -or $evaluatorApplied -or $helperApplied) {
        return 'Partial'
    }

    $translatorText = [System.IO.File]::ReadAllText($translator)
    $evaluatorText = [System.IO.File]::ReadAllText($evaluator)
    $requiredTranslatorAnchors = @(
        'if (terminator.Opcode == "SBranch")',
        'private static bool IsBranch(string opcode) =>',
        'var leaders = new SortedSet<uint> { instructions[0].Pc };',
        'if (terminator.Opcode == "SEndpgm")',
        'private bool HasSameScalarDefinitions('
    )
    foreach ($anchor in $requiredTranslatorAnchors) {
        if ($translatorText.IndexOf($anchor, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Anchor translator V76.0.6 ausente: $anchor"
        }
    }
    $requiredEvaluatorAnchors = @(
        'if (instruction.Opcode is "SSetpcB64" or "SSwappcB64")',
        'if (instruction.Opcode is "SLshlB64" or "SLshrB64")'
    )
    foreach ($anchor in $requiredEvaluatorAnchors) {
        if ($evaluatorText.IndexOf($anchor, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Anchor evaluator V76.0.6 ausente: $anchor"
        }
    }
    return 'Ready'
}

function Assert-V7606Installed {
    param([string]$RepoRoot)
    Assert-V76051Installed $RepoRoot
    if (-not (Test-FileContains (Join-Path $RepoRoot $TranslatorRel) $V7606TranslatorMarkers)) {
        throw 'Marcadores translator V76.0.6.1 incompletos.'
    }
    if (-not (Test-FileContains (Join-Path $RepoRoot $EvaluatorRel) $V7606EvaluatorMarkers)) {
        throw 'Marcadores scalar evaluator V76.0.6.1 incompletos.'
    }
    if (-not (Test-FileContains (Join-Path $RepoRoot $IndirectHelperRel) @(
        'TryEmitIndirectPcTransferV7606',
        'BitwiseAnd64(',
        'SSwappcB64'
    ))) {
        throw 'Helper indirect control V76.0.6.1 ausente/incompleto.'
    }
}
