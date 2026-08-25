param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Text([string]$Rel) {
    $path = Join-Path $RepoRoot $Rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Arquivo requerido ausente: $Rel"
    }
    return [System.IO.File]::ReadAllText($path)
}

function Write-Text([string]$Rel, [string]$Text) {
    $path = Join-Path $RepoRoot $Rel
    [System.IO.File]::WriteAllText($path, $Text, $Utf8NoBom)
}

function Replace-OnceRequired(
    [string]$Rel,
    [string]$Old,
    [string]$New,
    [string]$AlreadyMarker,
    [string]$Label
) {
    $text = Read-Text $Rel
    if (-not [string]::IsNullOrEmpty($AlreadyMarker) -and
        $text.IndexOf($AlreadyMarker, [System.StringComparison]::Ordinal) -ge 0) {
        Write-Host "  = $Label already"
        return
    }
    $idx = $text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($idx -lt 0) {
        throw "Anchor ausente para $Label em $Rel"
    }
    $updated = $text.Substring(0, $idx) + $New + $text.Substring($idx + $Old.Length)
    Write-Text $Rel $updated
    Write-Host "  * $Label"
}

function Replace-OnceOptional(
    [string]$Rel,
    [string]$Old,
    [string]$New,
    [string]$AlreadyMarker,
    [string]$Label
) {
    $text = Read-Text $Rel
    if (-not [string]::IsNullOrEmpty($AlreadyMarker) -and
        $text.IndexOf($AlreadyMarker, [System.StringComparison]::Ordinal) -ge 0) {
        Write-Host "  = $Label already"
        return
    }
    $idx = $text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($idx -lt 0) {
        Write-Host "  ! $Label anchor not found; optional telemetry/default left unchanged" -ForegroundColor Yellow
        return
    }
    $updated = $text.Substring(0, $idx) + $New + $text.Substring($idx + $Old.Length)
    Write-Text $Rel $updated
    Write-Host "  * $Label"
}

$alu = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs'
$translator = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
$presenter = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'

# ---------------------------------------------------------------------------
# ALU: V_CVT_PK_U16_U32 + V_DOT2C_F32_F16
# ---------------------------------------------------------------------------
$packAnchor = @'
                // [V74.0.56.9][RDNA2_POST_PS_STUDIOS_SHADER_FIX]
                case "VCvtPkI16I32":
'@
$packInsert = @'
                // V76.0.5.1: GFX10/RDNA2 unsigned i32 -> packed u16 conversion.
                // Saturate each source to 0xffff before packing.
                case "VCvtPkU16U32":
                {
                    var first = Ext(
                        38u,
                        _uintType,
                        GetRawSource(instruction, 0),
                        UInt(0xFFFFu));
                    var second = Ext(
                        38u,
                        _uintType,
                        GetRawSource(instruction, 1),
                        UInt(0xFFFFu));
                    result = BitwiseOr(
                        BitwiseAnd(first, UInt(0xFFFFu)),
                        ShiftLeftLogical(
                            BitwiseAnd(second, UInt(0xFFFFu)),
                            UInt(16)));
                    break;
                }
                // V76.0.5.1: V_DOT2C_F32_F16 is the VOP2 accumulate form.
                case "VDot2cF32F16":
                {
                    var packedA = GetRawSource(instruction, 0);
                    var packedB = GetRawSource(instruction, 1);
                    var aLow = Bitcast(_floatType, EmitHalfToFloat(packedA));
                    var aHigh = Bitcast(
                        _floatType,
                        EmitHalfToFloat(ShiftRightLogical(packedA, UInt(16))));
                    var bLow = Bitcast(_floatType, EmitHalfToFloat(packedB));
                    var bHigh = Bitcast(
                        _floatType,
                        EmitHalfToFloat(ShiftRightLogical(packedB, UInt(16))));
                    var oldDestination = Bitcast(_floatType, LoadV(destination));
                    var lowProduct = _module.AddInstruction(
                        SpirvOp.FMul,
                        _floatType,
                        aLow,
                        bLow);
                    var highProduct = _module.AddInstruction(
                        SpirvOp.FMul,
                        _floatType,
                        aHigh,
                        bHigh);
                    var dot = _module.AddInstruction(
                        SpirvOp.FAdd,
                        _floatType,
                        lowProduct,
                        highProduct);
                    result = Bitcast(
                        _uintType,
                        _module.AddInstruction(
                            SpirvOp.FAdd,
                            _floatType,
                            oldDestination,
                            dot));
                    break;
                }
                // [V74.0.56.9][RDNA2_POST_PS_STUDIOS_SHADER_FIX]
                case "VCvtPkI16I32":
'@
$aluText = Read-Text $alu
$hasPack = $aluText.IndexOf('case "VCvtPkU16U32"', [System.StringComparison]::Ordinal) -ge 0
$hasDot = $aluText.IndexOf('case "VDot2cF32F16"', [System.StringComparison]::Ordinal) -ge 0
if ($hasPack -xor $hasDot) {
    throw 'Estado parcial ALU: apenas um de VCvtPkU16U32/VDot2cF32F16 existe.'
}
if (-not $hasPack) {
    Replace-OnceRequired $alu $packAnchor $packInsert 'case "VCvtPkU16U32"' 'packed-u16 + dot2c-f16'
}
else {
    Write-Host '  = packed-u16 + dot2c-f16 already'
}

$falseOld = '            else if (opcode is "VCmpFF32" or "VCmpxFF32" or "VCmpFI32" or "VCmpFU32")'
$falseNew = @'
            else if (opcode is
                     "VCmpFF32" or "VCmpxFF32" or
                     "VCmpFI32" or "VCmpxFI32" or
                     "VCmpFU32" or "VCmpxFU32")
'@
Replace-OnceRequired $alu $falseOld $falseNew '"VCmpxFI32" or' 'vcmpx-false-i32-u32'

$trueOld = '            else if (opcode is "VCmpTruF32" or "VCmpxTruF32" or "VCmpTI32" or "VCmpTU32")'
$trueNew = @'
            else if (opcode is
                     "VCmpTruF32" or "VCmpxTruF32" or
                     "VCmpTI32" or "VCmpxTI32" or
                     "VCmpTU32" or "VCmpxTU32")
'@
Replace-OnceRequired $alu $trueOld $trueNew '"VCmpxTI32" or' 'vcmpx-true-i32-u32'

$bitcmpAnchor = @'
            var left = GetRawSource(instruction, 0);
            var right = GetRawSource(instruction, 1);
            if (instruction.Opcode is "SBitcmp0B32" or "SBitcmp1B32")
'@
$bitcmpNew = @'
            if (instruction.Opcode is "SBitcmp0B64" or "SBitcmp1B64")
            {
                var left64 = GetRawSource64(instruction, 0);
                var bitIndex32 = BitwiseAnd(GetRawSource(instruction, 1), UInt(63));
                var bitIndex64 = _module.AddInstruction(
                    SpirvOp.UConvert,
                    _ulongType,
                    bitIndex32);
                var shifted64 = ShiftRightLogical64(left64, bitIndex64);
                var isSet64 = IsNotZero64(
                    _module.AddInstruction(
                        SpirvOp.BitwiseAnd,
                        _ulongType,
                        shifted64,
                        _module.Constant64(_ulongType, 1)));
                Store(
                    _scc,
                    instruction.Opcode == "SBitcmp1B64"
                        ? isSet64
                        : _module.AddInstruction(
                            SpirvOp.LogicalNot,
                            _boolType,
                            isSet64));
                return true;
            }

            var left = GetRawSource(instruction, 0);
            var right = GetRawSource(instruction, 1);
            if (instruction.Opcode is "SBitcmp0B32" or "SBitcmp1B32")
'@
Replace-OnceRequired $alu $bitcmpAnchor $bitcmpNew 'instruction.Opcode is "SBitcmp0B64"' 's-bitcmp-b64'

# ---------------------------------------------------------------------------
# Translator: S_BARRIER + DS_SWIZZLE_B32 + immutable feature tracking
# ---------------------------------------------------------------------------
$translatorText = Read-Text $translator
if ($translatorText.IndexOf('EmitStageBarrierV7604();', [System.StringComparison]::Ordinal) -ge 0) {
    $barrierHelper = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.BarriersV7604.cs'
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $barrierHelper) -PathType Leaf)) {
        throw 'Gen5SpirvTranslator.cs chama EmitStageBarrierV7604, mas o helper V7604 nao existe em src.'
    }
    $helperText = Read-Text $barrierHelper
    if ($helperText.IndexOf('UInt(0x948)', [System.StringComparison]::Ordinal) -lt 0) {
        $helperOld = '                var semantics = UInt(0x108); // AcquireRelease | WorkgroupMemory'
        $helperNew = @'
                // V76.0.5.1: AcquireRelease + UniformMemory + WorkgroupMemory + ImageMemory.
                var semantics = UInt(0x948);
'@
        Replace-OnceRequired $barrierHelper $helperOld $helperNew 'UInt(0x948)' 's-barrier-v7604-compute-semantics'
    }
    else {
        Write-Host '  = s-barrier-v7604-compute-semantics already'
    }
}
else {
    $barrierOld = '                    var semantics = UInt(0x108);'
    $barrierNew = @'
                    // V76.0.5.1: AcquireRelease + UniformMemory +
                    // WorkgroupMemory + ImageMemory.
                    var semantics = UInt(0x948);
'@
    Replace-OnceRequired $translator $barrierOld $barrierNew 'var semantics = UInt(0x948);' 's-barrier-compute-semantics'
}

$dsAnchor = '                case "DsReadB32":'
$dsInsert = @'
                case "DsSwizzleB32":
                {
                    if (_subgroupInvocationIdInput == 0 ||
                        instruction.Sources.Count < 1 ||
                        instruction.Destinations.Count < 1)
                    {
                        error = "DS_SWIZZLE_B32 requires subgroup lane, DATA0 and VDST";
                        return false;
                    }

                    // V76.0.5.1: DS offset is a lane permutation pattern.
                    var pattern = control.Offset0 | (control.Offset1 << 8);
                    var lane = GuestWaveLane();
                    uint targetLane;
                    if ((pattern & 0x8000u) != 0)
                    {
                        var laneInQuad = BitwiseAnd(lane, UInt(3));
                        var selected = UInt(pattern & 3);
                        for (var index = 1u; index < 4; index++)
                        {
                            selected = _module.AddInstruction(
                                SpirvOp.Select,
                                _uintType,
                                _module.AddInstruction(
                                    SpirvOp.IEqual,
                                    _boolType,
                                    laneInQuad,
                                    UInt(index)),
                                UInt((pattern >> checked((int)(index * 2))) & 3),
                                selected);
                        }

                        targetLane = IAdd(
                            BitwiseAnd(lane, UInt(0xFFFF_FFFCu)),
                            selected);
                    }
                    else
                    {
                        var andMask = UInt(pattern & 0x1Fu);
                        var orMask = UInt((pattern >> 5) & 0x1Fu);
                        var xorMask = UInt((pattern >> 10) & 0x1Fu);
                        var lowFive = _module.AddInstruction(
                            SpirvOp.BitwiseXor,
                            _uintType,
                            BitwiseOr(BitwiseAnd(lane, andMask), orMask),
                            xorMask);
                        targetLane = BitwiseAnd(lowFive, UInt(0x1Fu));
                    }

                    // Match the existing DPP lowering: guest wave64 is split
                    // into host subgroup halves, so shuffle index remains 0..31.
                    targetLane = BitwiseAnd(targetLane, UInt(31));
                    var source = GetRawSource(instruction, 0);
                    var swizzled = _module.AddInstruction(
                        SpirvOp.GroupNonUniformShuffle,
                        _uintType,
                        UInt(3),
                        source,
                        targetLane);
                    StoreV(instruction.Destinations[0].Value, swizzled);
                    return true;
                }
                case "DsReadB32":
'@
Replace-OnceRequired $translator $dsAnchor $dsInsert 'case "DsSwizzleB32"' 'ds-swizzle-b32'

$featureDeclOld = '            var usesDsAddtid = false;'
$featureDeclNew = @'
            var usesDsAddtid = false;
            var usesDsSwizzle = false;
'@
Replace-OnceRequired $translator $featureDeclOld $featureDeclNew 'var usesDsSwizzle = false;' 'ds-swizzle-feature-decl'

$featureTrackOld = @'
                usesDsAddtid |= instruction.Opcode is
                    "DsStoreAddtidB32" or
                    "DsReadAddtidB32";
'@
$featureTrackNew = @'
                usesDsAddtid |= instruction.Opcode is
                    "DsStoreAddtidB32" or
                    "DsReadAddtidB32";
                usesDsSwizzle |= instruction.Opcode == "DsSwizzleB32";
'@
Replace-OnceRequired $translator $featureTrackOld $featureTrackNew 'usesDsSwizzle |= instruction.Opcode' 'ds-swizzle-feature-track'

$featureFinalOld = @'
                    usesMbcnt ||
                    usesDsAddtid);
'@
$featureFinalNew = @'
                    usesMbcnt ||
                    usesDsAddtid ||
                    usesDsSwizzle);
'@
Replace-OnceRequired $translator $featureFinalOld $featureFinalNew 'usesDsAddtid ||' 'ds-swizzle-feature-final'

# V76.0.4 soft-fail, if present, becomes opt-in instead of default-on.
$softFailRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftFailV7604.cs'
$softFailPath = Join-Path $RepoRoot $softFailRel
if (Test-Path -LiteralPath $softFailPath -PathType Leaf) {
    $softText = Read-Text $softFailRel
    if ($softText.IndexOf('semantic corruption must never be the default', [System.StringComparison]::Ordinal) -lt 0) {
        $softOld = @'
        private static readonly bool SoftFailEnabled =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_SHADER_SOFT_FAIL"),
                "0",
                StringComparison.Ordinal);
'@
        $softNew = @'
        // V76.0.5.1: semantic corruption must never be the default. Enable
        // explicitly only for diagnostics with SHARPEMU_SHADER_SOFT_FAIL=1.
        private static readonly bool SoftFailEnabled =
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_SHADER_SOFT_FAIL"),
                "1",
                StringComparison.Ordinal);
'@
        Replace-OnceRequired $softFailRel $softOld $softNew 'semantic corruption must never be the default' 'v7604-soft-fail-opt-in'
    }
    else {
        Write-Host '  = v7604-soft-fail-opt-in already'
    }
}

# V76.0.3 cache helper, if it landed in src without its referenced disk-cache
# class, must not make the whole solution uncompilable. It is superseded by the
# V76.0.5 binary cache because the V7603 live Gen5SpirvShader cache can reuse
# per-dispatch metadata incorrectly.
$v3CacheRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.CacheV7603.cs'
$v3CachePath = Join-Path $RepoRoot $v3CacheRel
if (Test-Path -LiteralPath $v3CachePath -PathType Leaf) {
    $diskCacheDefinition = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'src') -Recurse -Filter '*.cs' -File |
        Select-String -SimpleMatch 'class SpirvShaderDiskCache' -List |
        Select-Object -First 1
    if ($null -eq $diskCacheDefinition) {
        $v3Text = Read-Text $v3CacheRel
        if ($v3Text.IndexOf('SpirvShaderDiskCache.TryLoad', [System.StringComparison]::Ordinal) -ge 0) {
            $v3LoadOld = @'
        // Disk: only SPIR-V bytes — metadata still requires a live translation.
        // Keep disk path for future full-artifact serialization; count as miss for now
        // if memory miss so translation still runs once per process.
        if (SpirvShaderDiskCache.TryLoad(key, out _))
        {
            // Bytes present but without bindings we cannot rebuild Gen5SpirvShader safely.
            // Leave as miss; Store will refresh disk after translate.
        }

'@
            $v3LoadNew = @'
        // V76.0.5.1: the V7603 disk-cache dependency was not shipped with the
        // original package. The wrapper is superseded by VulkanShaderBinaryCacheV7605.

'@
            Replace-OnceRequired $v3CacheRel $v3LoadOld $v3LoadNew 'V7603 disk-cache dependency was not shipped' 'v7603-missing-disk-cache-load'
        }
        $v3Text = Read-Text $v3CacheRel
        if ($v3Text.IndexOf('SpirvShaderDiskCache.Store', [System.StringComparison]::Ordinal) -ge 0) {
            Replace-OnceRequired $v3CacheRel '        SpirvShaderDiskCache.Store(key, shader.Spirv);' '        // V76.0.5.1: superseded disk store removed.' 'superseded disk store removed' 'v7603-missing-disk-cache-store'
        }
    }
}

# ---------------------------------------------------------------------------
# Presenter: defaults and instrumentation are surgical; core shader patches do
# not fail just because a telemetry anchor moved in a later RAD/UI patch.
# ---------------------------------------------------------------------------
$catchFramesOld = @'
            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 8;
'@
$catchFramesNew = @'
            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 12; // V76.0.5.1
'@
Replace-OnceOptional $presenter $catchFramesOld $catchFramesNew ': 12; // V76.0.5.1' 'bink-catchup-frames'

$catchBudgetOld = @'
                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 6));
'@
$catchBudgetNew = @'
                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 10)); // V76.0.5.1
'@
Replace-OnceOptional $presenter $catchBudgetOld $catchBudgetNew ': 10)); // V76.0.5.1' 'bink-catchup-budget'

$perfFieldsOld = '    private static long _perfSpirvCompilations;'
$perfFieldsNew = @'
    private static long _perfSpirvCompilations;

    // V76.0.5.1: opt-in host-side compute dispatch timing.
    private static readonly bool TraceComputeDispatchTimingV7605 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_COMPUTE_DISPATCH_TIMING"),
            "1",
            StringComparison.Ordinal);
    private static readonly double TraceComputeDispatchThresholdMsV7605 =
        double.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_COMPUTE_DISPATCH_THRESHOLD_MS"),
            System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture,
            out var computeDispatchThresholdMsV7605) &&
        computeDispatchThresholdMsV7605 >= 0
            ? computeDispatchThresholdMsV7605
            : 5.0;
    private static long _v7605ComputeDispatchTimingCount;
'@
Replace-OnceOptional $presenter $perfFieldsOld $perfFieldsNew 'TraceComputeDispatchTimingV7605' 'compute-timing-fields'

$computeFinallyOld = @'
                Interlocked.Add(
                    ref _perfDrawTicks,
                    Stopwatch.GetTimestamp() - perfStart);
'@
$computeFinallyNew = @'
                var elapsedTicksV7605 = Stopwatch.GetTimestamp() - perfStart;
                Interlocked.Add(ref _perfDrawTicks, elapsedTicksV7605);
                if (TraceComputeDispatchTimingV7605)
                {
                    var elapsedMsV7605 = elapsedTicksV7605 * 1000.0 /
                        Stopwatch.Frequency;
                    if (elapsedMsV7605 >= TraceComputeDispatchThresholdMsV7605)
                    {
                        var timingCountV7605 = Interlocked.Increment(
                            ref _v7605ComputeDispatchTimingCount);
                        Console.Error.WriteLine(
                            $"[COMPUTE-TIMING][V76.0.5.1] count={timingCountV7605} " +
                            $"host_ms={elapsedMsV7605:F3} cs=0x{work.ShaderAddress:X16} " +
                            $"groups={work.GroupCountX}x{work.GroupCountY}x{work.GroupCountZ} " +
                            $"base={work.BaseGroupX}x{work.BaseGroupY}x{work.BaseGroupZ} " +
                            $"local={work.LocalSizeX}x{work.LocalSizeY}x{work.LocalSizeZ} " +
                            $"wave={work.WaveLaneCount} indirect={(work.IsIndirect ? 1 : 0)} " +
                            $"textures={work.Textures.Count} globals={work.GlobalMemoryBuffers.Count}");
                    }
                }
'@
$presenterAfterFields = Read-Text $presenter
if ($presenterAfterFields.IndexOf('TraceComputeDispatchTimingV7605', [System.StringComparison]::Ordinal) -ge 0) {
    Replace-OnceOptional $presenter $computeFinallyOld $computeFinallyNew '[COMPUTE-TIMING][V76.0.5.1]' 'compute-timing-body'
}
else {
    Write-Host '  ! compute-timing-body skipped because timing fields anchor moved' -ForegroundColor Yellow
}

$presentOld = '            CheckSwapchainResult(presentResult, "vkQueuePresentKHR");'
$presentNew = @'
            CheckSwapchainResult(presentResult, "vkQueuePresentKHR");
            VulkanPresentCadenceV7605.NoteSuccessfulPresent();
'@
Replace-OnceRequired $presenter $presentOld $presentNew 'VulkanPresentCadenceV7605.NoteSuccessfulPresent();' 'present-cadence-hook'

Write-Host '[V76.0.5.1] Adaptive source patch completed.'
