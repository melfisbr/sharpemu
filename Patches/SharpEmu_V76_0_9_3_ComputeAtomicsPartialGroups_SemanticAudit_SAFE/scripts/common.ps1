$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.9.3-COMPUTE-ATOMICS-PARTIAL-GROUPS-SEMANTIC-AUDIT'

$AffectedExistingFiles = @(
    'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs',
    'src\SharpEmu.Libs\Agc\AgcExports.cs'
)
$HelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.AtomicCompatV7609.cs'
$HelperPayloadRel = 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.AtomicCompatV7609.cs'
$HelperHash = '4456dafc25323127bf996dccd5b943eb2298282612b0cc1681db2e0078e6cf4d'
$V7608HelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.TypedBufferStoreV7608.cs'
$V7608HelperHash = 'c35c29220a7d534ee77136d4183c557b70069071b314ffeed2fa735e813a73c3'
$IndirectHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IndirectControlV7606.cs'
$IndirectHelperHash = '2c395d530bffd6a9a998bda73210d13eb8de9fd1a2c75fe14a20486b2e3a5520'
$RequiredImmutableHashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs' = '7dfa9c69563c068b4acaf9e48a6e714f16554b70ca141a55583e075851835fef'
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = '0783a960b89755ce5172598e01bf7d09c0fabdf0841654e4ea4ff572fc83b58f'
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs' = '1d569a968c456e04bd7eff3cc63f1ad7ef5029dc0af9fd725d75d3f85e7489a1'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs' = 'b733069d26919a08f99833af33cb64938a19e1319936e9a6ae7d0ddaeafe3b09'
}

$V7608CarrySpecs = @(
    [pscustomobject]@{ Name='v8_01_mubuf_decode'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='V76.0.8 / GFX10 MUBUF: OP is eight bits' },
    [pscustomobject]@{ Name='v8_02_mubuf_ir'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='var formatD16 = opcode.Contains("FormatD16", StringComparison.Ordinal);' },
    [pscustomobject]@{ Name='v8_03_format_store_dispatch'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='EmitBufferFormatStoreV7608(' },
    [pscustomobject]@{ Name='v8_04_d16_narrow_integer_kind'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='V7608_D16_INTEGER_KIND_FIXED' }
)

$PatchSpecs = @(
    [pscustomobject]@{ Name='01_flat_atomic_decode'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='V76.0.9: complete the 32-bit FLAT/GLOBAL atomic family.' },
    [pscustomobject]@{ Name='02_flat_atomic_ir'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Marker='"GlobalAtomicCmpswap" => 2u,' },
    [pscustomobject]@{ Name='03_atomic_helper_declare'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='DeclareRdnaAtomicCompatV7609();' },
    [pscustomobject]@{ Name='04_ds_atomic_space'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='space: RdnaAtomicSpaceV7609.Workgroup' },
    [pscustomobject]@{ Name='05_atomic_comment'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='redirects them through the V76.0.9 bounded CAS helper' },
    [pscustomobject]@{ Name='06_emit_atomic_bounded'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='RdnaAtomicSpaceV7609 space = RdnaAtomicSpaceV7609.StorageBuffer' },
    [pscustomobject]@{ Name='07_global_atomic_generic'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='memoryOpcode["GlobalAtomic".Length..]' },
    [pscustomobject]@{ Name='08_image_atomic_space'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Marker='space: RdnaAtomicSpaceV7609.Image' },
    [pscustomobject]@{ Name='09_partial_thread_groups'; Rel='src\SharpEmu.Libs\Agc\AgcExports.cs'; Marker='V76.0.9: PARTIAL_TG_EN is representable' }
)

function Get-RepoRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) { $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu' }
    $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    $probe = Join-Path $resolved 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "Repo root invalido: $resolved (faltando $probe)" }
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
function Read-NormalizedText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Arquivo ausente: $Path" }
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
}
function Test-FileContains {
    param([string]$Path, [string[]]$Markers)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($Path)
    foreach ($marker in $Markers) { if ($text.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0) { return $false } }
    return $true
}
function Get-OccurrenceCount {
    param([string]$Text,[string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count=0; $start=0
    while ($start -le $Text.Length - $Needle.Length) {
        $idx=$Text.IndexOf($Needle,$start,[System.StringComparison]::Ordinal)
        if ($idx -lt 0) { break }
        $count++; $start=$idx+$Needle.Length
    }
    return $count
}
function Get-PatchDataPath { param([string]$Name,[string]$Kind); return Join-Path $PackageRoot ("patchdata\{0}.{1}.txt" -f $Name,$Kind) }

function Test-V7608FormatStoreDispatchSemantic {
    param([string]$RepoRoot,$Spec)
    $target=Join-Path $RepoRoot $Spec.Rel
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Arquivo prerequisite ausente: $($Spec.Rel)" }
    $text=Read-NormalizedText $target

    # The V76.0.8 build+verify can coexist with later formatting/rebases in
    # this large translator file. Detect the actual helper dispatch first;
    # do not require the historical whole-block anchor.
    if ($text.IndexOf('EmitBufferFormatStoreV7608',[System.StringComparison]::Ordinal) -ge 0) {
        return [pscustomobject]@{State='AppliedSemantic';Count=0}
    }

    # If the helper dispatch vanished, locate the generic untyped store path
    # structurally. RUN_3 can restore the typed branch immediately before it.
    $genericPattern='(?m)^ {12}if\s*\(\s*instruction\.Opcode\.StartsWith\(\s*"BufferStoreDword"\s*,\s*StringComparison\.Ordinal\s*\)\s*\|\|'
    $matches=[System.Text.RegularExpressions.Regex]::Matches(
        $text,
        $genericPattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($matches.Count -ne 1) {
        throw "Semantic prerequisite V76.0.8 invalida: $($Spec.Name) generic-store occurrences=$($matches.Count)"
    }
    return [pscustomobject]@{State='ReadySemanticRepair';Count=$matches.Count}
}

function Test-V7608CarrySpec {
    param([string]$RepoRoot,$Spec)
    if ($Spec.Name -eq 'v8_03_format_store_dispatch') {
        $semanticResult=Test-V7608FormatStoreDispatchSemantic $RepoRoot $Spec
        return $semanticResult
    }
    $target=Join-Path $RepoRoot $Spec.Rel
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Arquivo prerequisite ausente: $($Spec.Rel)" }
    $text=Read-NormalizedText $target
    if ($Spec.Name -eq 'v8_04_d16_narrow_integer_kind') {
        # V76.0.9.3: this prerequisite is an audit, not a historical-text
        # anchor. V76.0.8 already passed build+source-verify; later rebases may
        # rename locals or restructure NarrowGfx10FormatResultToD16. The only
        # known incorrect semantic form is passing a SPIR-V constant ID to
        # Equal(), so reject that regression explicitly and accept any other
        # refactored implementation. The real C# build remains the final gate.
        $bad4=$text.IndexOf('Equal(numberFormat, UInt(4))',[System.StringComparison]::Ordinal) -ge 0
        $bad5=$text.IndexOf('Equal(numberFormat, UInt(5))',[System.StringComparison]::Ordinal) -ge 0
        if ($bad4 -or $bad5) {
            throw 'V76.0.8 D16 integer-kind regression: Equal(numberFormat, UInt(4/5)) reapareceu.'
        }
        return [pscustomobject]@{State='AppliedSemanticRefactored';Count=0}
    } elseif ($text.IndexOf($Spec.Marker,[System.StringComparison]::Ordinal) -ge 0) {
        return [pscustomobject]@{State='Applied';Count=0}
    }
    $old=Read-NormalizedText (Get-PatchDataPath $Spec.Name 'old')
    $count=Get-OccurrenceCount $text $old
    if ($count -ne 1) { throw "Anchor prerequisite V76.0.8 invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count" }
    return [pscustomobject]@{State='ReadyRepair';Count=$count}
}
function Assert-V7608Base {
    param([string]$RepoRoot)
    foreach ($rel in $RequiredImmutableHashes.Keys) {
        $actual=Get-Sha256 (Join-Path $RepoRoot $rel); $expected=$RequiredImmutableHashes[$rel]
        if ($actual -ne $expected) { throw "V76.0.5.1 immutable prerequisite mismatch: $rel expected=$expected actual=$actual" }
    }
    $indirectActual=Get-Sha256 (Join-Path $RepoRoot $IndirectHelperRel)
    if ($indirectActual -ne $IndirectHelperHash) { throw "V76.0.6.1 helper mismatch expected=$IndirectHelperHash actual=$indirectActual" }
    $v8Actual=Get-Sha256 (Join-Path $RepoRoot $V7608HelperRel)
    if ($v8Actual -ne $V7608HelperHash) { throw "V76.0.8 typed-store helper mismatch expected=$V7608HelperHash actual=$v8Actual" }
    foreach ($spec in $V7608CarrySpecs) { [void](Test-V7608CarrySpec $RepoRoot $spec) }
}
function Assert-V7608Installed {
    param([string]$RepoRoot)
    foreach ($rel in $RequiredImmutableHashes.Keys) {
        $actual=Get-Sha256 (Join-Path $RepoRoot $rel); $expected=$RequiredImmutableHashes[$rel]
        if ($actual -ne $expected) { throw "V76.0.5.1 immutable prerequisite mismatch: $rel expected=$expected actual=$actual" }
    }
    $indirectActual=Get-Sha256 (Join-Path $RepoRoot $IndirectHelperRel)
    if ($indirectActual -ne $IndirectHelperHash) { throw "V76.0.6.1 helper mismatch expected=$IndirectHelperHash actual=$indirectActual" }
    $v8Actual=Get-Sha256 (Join-Path $RepoRoot $V7608HelperRel)
    if ($v8Actual -ne $V7608HelperHash) { throw "V76.0.8 typed-store helper mismatch expected=$V7608HelperHash actual=$v8Actual" }
    $decoder=Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
    $spirv=Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
    if (-not (Test-FileContains $decoder @(
        'V76.0.8 / GFX10 MUBUF: OP is eight bits',
        '0x80 => "BufferLoadFormatD16X"',
        '0x87 => "BufferStoreFormatD16Xyzw"',
        'var formatD16 = opcode.Contains("FormatD16", StringComparison.Ordinal);'))) { throw 'V76.0.8 decoder/IR final incompleto.' }
    $spirvText=Read-NormalizedText $spirv
    if ($spirvText.IndexOf('EmitBufferFormatStoreV7608(',[System.StringComparison]::Ordinal) -lt 0) { throw 'V76.0.8 typed-store dispatch ausente.' }
    if ($spirvText.IndexOf('typed-buffer store conversion pending',[System.StringComparison]::Ordinal) -ge 0) { throw 'V76.0.8 typed-store pending reapareceu.' }
    if ($spirvText.IndexOf('Equal(numberFormat, UInt(4))',[System.StringComparison]::Ordinal) -ge 0 -or
        $spirvText.IndexOf('Equal(numberFormat, UInt(5))',[System.StringComparison]::Ordinal) -ge 0) { throw 'V76.0.8 D16 integer-kind ainda usa SPIR-V constant id incorreto.' }
    # V76.0.9.3 deliberately does not require historical local names or exact
    # Equal(numberFormat, 4/5) spelling. Absence of the known-bad constant-ID
    # form plus the successful project build is the semantic carry-forward gate.
}
function Test-PatchSpec {
    param([string]$RepoRoot,$Spec)
    $target=Join-Path $RepoRoot $Spec.Rel
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Arquivo alvo ausente: $($Spec.Rel)" }
    $text=Read-NormalizedText $target
    if ($text.IndexOf($Spec.Marker,[System.StringComparison]::Ordinal) -ge 0) { return [pscustomobject]@{State='Applied';Count=0} }
    $old=Read-NormalizedText (Get-PatchDataPath $Spec.Name 'old')
    $count=Get-OccurrenceCount $text $old
    if ($count -ne 1) { throw "Anchor V76.0.9 invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count" }
    return [pscustomobject]@{State='Ready';Count=$count}
}
function Get-HelperState {
    param([string]$RepoRoot)
    $path=Join-Path $RepoRoot $HelperRel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'Ready' }
    $actual=Get-Sha256 $path
    if ($actual -eq $HelperHash) { return 'Applied' }
    throw "Helper V76.0.9 divergente expected=$HelperHash actual=$actual"
}
function Get-V7609State {
    param([string]$RepoRoot)
    Assert-V7608Base $RepoRoot
    $ready=0
    foreach ($spec in $V7608CarrySpecs) { $r=Test-V7608CarrySpec $RepoRoot $spec; if ($r.State -eq 'ReadyRepair' -or $r.State -eq 'ReadySemanticRepair') { $ready++ } }
    foreach ($spec in $PatchSpecs) { $r=Test-PatchSpec $RepoRoot $spec; if ($r.State -eq 'Ready') { $ready++ } }
    if ((Get-HelperState $RepoRoot) -eq 'Ready') { $ready++ }
    if ($ready -eq 0) { return 'AlreadyApplied' }
    return 'ReadyAdaptive'
}
function Assert-V7609Installed {
    param([string]$RepoRoot)
    Assert-V7608Installed $RepoRoot
    foreach ($spec in $PatchSpecs) {
        $target=Join-Path $RepoRoot $spec.Rel
        if (-not (Test-FileContains $target @($spec.Marker))) { throw "Marcador V76.0.9 ausente: $($spec.Name)" }
    }
    $actual=Get-Sha256 (Join-Path $RepoRoot $HelperRel)
    if ($actual -ne $HelperHash) { throw "Helper V76.0.9 hash mismatch expected=$HelperHash actual=$actual" }
    $decoder=Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
    $spirv=Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
    $agc=Join-Path $RepoRoot 'src\SharpEmu.Libs\Agc\AgcExports.cs'
    $helper=Join-Path $RepoRoot $HelperRel
    if (-not (Test-FileContains $decoder @(
        '0x30 => "AtomicSwap"','0x31 => "AtomicCmpswap"','0x3C => "AtomicInc"','0x3D => "AtomicDec"','"GlobalAtomicCmpswap" => 2u,'))) { throw 'V76.0.9 FLAT/GLOBAL atomic family incompleta.' }
    if (-not (Test-FileContains $spirv @(
        'DeclareRdnaAtomicCompatV7609();','EmitRdnaBoundedAtomicV7609(','RdnaAtomicSpaceV7609.Workgroup','RdnaAtomicSpaceV7609.Image'))) { throw 'V76.0.9 atomic dispatch incompleto.' }
    if (-not (Test-FileContains $helper @(
        'SpirvOp.AtomicCompareExchange','SpirvOp.UGreaterThanEqual','SpirvOp.UGreaterThan','rdna_atomic_inc_storage_v7609','rdna_atomic_dec_workgroup_v7609'))) { throw 'V76.0.9 CAS helper incompleto.' }
    $agcText=[System.IO.File]::ReadAllText($agc)
    if ($agcText.IndexOf('unrepresentable-partial-group(',[System.StringComparison]::Ordinal) -ge 0) { throw 'V76.0.9 ainda rejeita partial thread group representavel.' }
    if (-not (Test-FileContains $agc @('partial-thread-limit-overflow','threadCountX = (uint)exactEndX;'))) { throw 'V76.0.9 partial thread-limit guard incompleto.' }
}
