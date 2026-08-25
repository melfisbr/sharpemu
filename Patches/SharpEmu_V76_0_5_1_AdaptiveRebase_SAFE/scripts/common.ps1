$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.5.1-GEN5-VULKAN-ADAPTIVE-REBASE'

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

$BackendRel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$AluRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs'
$TranslatorRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'

$NewPayloadHashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = '0783a960b89755ce5172598e01bf7d09c0fabdf0841654e4ea4ff572fc83b58f'
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs' = '1d569a968c456e04bd7eff3cc63f1ad7ef5029dc0af9fd725d75d3f85e7489a1'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs' = 'b733069d26919a08f99833af33cb64938a19e1319936e9a6ae7d0ddaeafe3b09'
}

$BackendBaselineHash = '50a5d68e62281baf59ef5d43ce50fc973be5da5e69385e17613d936ab1b9bda2'
$BackendPayloadHash = '7dfa9c69563c068b4acaf9e48a6e714f16554b70ca141a55583e075851835fef'

$AcceptedPresenterHashes = @(
    '75e29c1ecfec9ce5969caa091a25926b133dfb8651eb7d815a3d237dd41a1816',
    'df4ab75ebfff208aac25c5638999d6d45220471c14c01383f58ccd6f4f76720e'
)
$AcceptedAluHashes = @(
    'e55271ee14316c6339b199a1b9aff268a07098618a7370c57c4592592aff0a72',
    '0db282edbe624dbe630855b9664f30ffb4d1aea06837ed46a0593079fc4387e3'
)
$AcceptedTranslatorHashes = @(
    '13edb9474c2b39c599b94c8195f65d0581bd3eef48033ab741030d09bd4dfab6',
    '67875b135f47695cf82bdbee8cb78e923c18a8c55daa5da038de0daefb68cb14'
)

$AluMarkers = @(
    'case "VCvtPkU16U32"',
    'case "VDot2cF32F16"',
    'instruction.Opcode is "SBitcmp0B64"',
    '"VCmpxFI32" or',
    '"VCmpxTI32" or'
)
$TranslatorMarkers = @(
    'case "DsSwizzleB32"',
    'var usesDsSwizzle = false;',
    'usesDsSwizzle |= instruction.Opcode'
)

function Get-SourceState {
    param([string]$RepoRoot)

    $details = New-Object System.Collections.Generic.List[string]
    $unknown = New-Object System.Collections.Generic.List[string]

    $backendPath = Join-Path $RepoRoot $BackendRel
    $backendHash = Get-Sha256 $backendPath
    if ($backendHash -eq $BackendPayloadHash) {
        $details.Add("PAYLOAD $BackendRel $backendHash")
    }
    elseif ($backendHash -eq $BackendBaselineHash) {
        $details.Add("BASELINE $BackendRel $backendHash")
    }
    else {
        $unknown.Add("UNKNOWN $BackendRel $backendHash")
    }

    $presenterPath = Join-Path $RepoRoot $PresenterRel
    $presenterHash = Get-Sha256 $presenterPath
    if ($AcceptedPresenterHashes -contains $presenterHash) {
        $details.Add("REBASE_TARGET $PresenterRel $presenterHash")
    }
    elseif (Test-FileContains $presenterPath @('VulkanPresentCadenceV7605.NoteSuccessfulPresent();')) {
        $details.Add("PATCHED_MARKERS $PresenterRel $presenterHash")
    }
    else {
        $unknown.Add("UNKNOWN $PresenterRel $presenterHash")
    }

    $aluPath = Join-Path $RepoRoot $AluRel
    $aluHash = Get-Sha256 $aluPath
    if ($AcceptedAluHashes -contains $aluHash) {
        $details.Add("REBASE_TARGET $AluRel $aluHash")
    }
    elseif (Test-FileContains $aluPath $AluMarkers) {
        $details.Add("PATCHED_MARKERS $AluRel $aluHash")
    }
    else {
        $unknown.Add("UNKNOWN $AluRel $aluHash")
    }

    $translatorPath = Join-Path $RepoRoot $TranslatorRel
    $translatorHash = Get-Sha256 $translatorPath
    if ($AcceptedTranslatorHashes -contains $translatorHash) {
        $details.Add("REBASE_TARGET $TranslatorRel $translatorHash")
    }
    elseif (Test-FileContains $translatorPath $TranslatorMarkers) {
        $details.Add("PATCHED_MARKERS $TranslatorRel $translatorHash")
    }
    else {
        $unknown.Add("UNKNOWN $TranslatorRel $translatorHash")
    }

    foreach ($rel in $NewPayloadHashes.Keys) {
        $path = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $details.Add("ABSENT $rel")
            continue
        }
        $hash = Get-Sha256 $path
        if ($hash -eq $NewPayloadHashes[$rel]) {
            $details.Add("PAYLOAD $rel $hash")
        }
        else {
            $unknown.Add("UNKNOWN $rel $hash")
        }
    }

    if ($unknown.Count -gt 0) {
        return [pscustomobject]@{ State='Divergent'; Details=$details; Unknown=$unknown }
    }

    $backendApplied = $backendHash -eq $BackendPayloadHash
    $aluApplied = Test-FileContains $aluPath $AluMarkers
    $translatorApplied = Test-FileContains $translatorPath $TranslatorMarkers
    $presentApplied = Test-FileContains $presenterPath @('VulkanPresentCadenceV7605.NoteSuccessfulPresent();')
    $newApplied = $true
    foreach ($rel in $NewPayloadHashes.Keys) {
        if ((Get-Sha256 (Join-Path $RepoRoot $rel)) -ne $NewPayloadHashes[$rel]) {
            $newApplied = $false
            break
        }
    }

    if ($backendApplied -and $aluApplied -and $translatorApplied -and $presentApplied -and $newApplied) {
        return [pscustomobject]@{ State='AlreadyApplied'; Details=$details; Unknown=$unknown }
    }

    return [pscustomobject]@{ State='ReadyAdaptive'; Details=$details; Unknown=$unknown }
}

function Assert-InstalledMarkers {
    param([string]$RepoRoot)

    $backendActual = Get-Sha256 (Join-Path $RepoRoot $BackendRel)
    if ($backendActual -ne $BackendPayloadHash) {
        throw "Backend V76.0.5.1 nao instalado: $backendActual"
    }

    foreach ($rel in $NewPayloadHashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        if ($actual -ne $NewPayloadHashes[$rel]) {
            throw "Payload hash mismatch: $rel expected=$($NewPayloadHashes[$rel]) actual=$actual"
        }
    }

    if (-not (Test-FileContains (Join-Path $RepoRoot $AluRel) $AluMarkers)) {
        throw 'Marcadores ALU V76.0.5.1 incompletos.'
    }
    if (-not (Test-FileContains (Join-Path $RepoRoot $TranslatorRel) $TranslatorMarkers)) {
        throw 'Marcadores translator V76.0.5.1 incompletos.'
    }
    if (-not (Test-FileContains (Join-Path $RepoRoot $PresenterRel) @('VulkanPresentCadenceV7605.NoteSuccessfulPresent();'))) {
        throw 'Hook de present cadence V76.0.5.1 ausente.'
    }
}
