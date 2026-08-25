param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Text([string]$Rel) {
    $path = Join-Path $RepoRoot $Rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo requerido ausente: $Rel" }
    return [System.IO.File]::ReadAllText($path)
}
function Write-Text([string]$Rel, [string]$Text) {
    [System.IO.File]::WriteAllText((Join-Path $RepoRoot $Rel), $Text, $Utf8NoBom)
}
function Replace-OnceRequired([string]$Rel,[string]$Old,[string]$New,[string]$Marker,[string]$Label) {
    $text = Read-Text $Rel
    if ($text.IndexOf($Marker, [System.StringComparison]::Ordinal) -ge 0) {
        Write-Host "  = $Label already"
        return
    }
    $idx = $text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($idx -lt 0) { throw "Anchor ausente para $Label em $Rel" }
    if ($text.IndexOf($Old, $idx + $Old.Length, [System.StringComparison]::Ordinal) -ge 0) {
        throw "Anchor ambiguo para $Label em $Rel"
    }
    Write-Text $Rel ($text.Substring(0,$idx) + $New + $text.Substring($idx + $Old.Length))
    Write-Host "  * $Label"
}

$translator = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
$evaluator = 'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs'

$old = @'
            if (terminator.Opcode == "SBranch")
            {
'@
$new = @'
            if (IsIndirectPcTransferV7606(terminator.Opcode))
            {
                return TryEmitIndirectPcTransferV7606(blocks, terminator, out error);
            }

            if (terminator.Opcode == "SBranch")
            {
'@
Replace-OnceRequired $translator $old $new 'IsIndirectPcTransferV7606(terminator.Opcode)' 'emit-indirect-pc-terminator'

$old = @'
        private static bool IsBranch(string opcode) =>
            opcode == "SBranch" ||
            opcode.StartsWith("SCbranch", StringComparison.Ordinal);
'@
$new = @'
        private static bool IsBranch(string opcode) =>
            opcode == "SBranch" ||
            opcode.StartsWith("SCbranch", StringComparison.Ordinal) ||
            IsIndirectPcTransferV7606(opcode);
'@
Replace-OnceRequired $translator $old $new 'IsIndirectPcTransferV7606(opcode);' 'classify-indirect-pc-as-branch'

$old = '            var leaders = new SortedSet<uint> { instructions[0].Pc };'
$new = @'
            var leaders = new SortedSet<uint> { instructions[0].Pc };
            var hasIndirectPcTransferV7606 = instructions.Any(
                static instruction => IsIndirectPcTransferV7606(instruction.Opcode));
            if (hasIndirectPcTransferV7606)
            {
                // V76.0.6: an SGPR target can legally point at any decoded
                // instruction. Only indirect-control shaders pay this finer
                // CFG granularity; normal shaders keep the previous blocks.
                foreach (var instruction in instructions)
                {
                    leaders.Add(instruction.Pc);
                }
            }
'@
Replace-OnceRequired $translator $old $new 'hasIndirectPcTransferV7606' 'indirect-target-block-granularity'

$old = @'
                if (terminator.Opcode == "SBranch")
                {
                    if (TryGetBranchTargetPc(terminator, out var targetPc) &&
'@
$new = @'
                if (IsIndirectPcTransferV7606(terminator.Opcode))
                {
                    // Runtime SGPR target is unknown to this static definition
                    // pass. Conservatively model every decoded block as a
                    // possible successor. Exact same-PC resource bindings are
                    // handled specially by HasSameScalarDefinitions below.
                    for (var targetBlock = 0; targetBlock < blocks.Count; targetBlock++)
                    {
                        AddEdge(blockIndex, targetBlock);
                    }
                    continue;
                }

                if (terminator.Opcode == "SBranch")
                {
                    if (TryGetBranchTargetPc(terminator, out var targetPc) &&
'@
Replace-OnceRequired $translator $old $new 'Conservatively model every decoded block' 'indirect-cfg-predecessors'

$old = @'
            if (firstRegister + registerCount > ScalarRegisterCount ||
                !_scalarDefinitionsBeforePc.TryGetValue(candidatePc, out var candidate) ||
                !_scalarDefinitionsBeforePc.TryGetValue(targetPc, out var target))
            {
                return false;
            }
'@
$new = @'
            if (firstRegister + registerCount > ScalarRegisterCount)
            {
                return false;
            }

            // V76.0.6: a binding recorded for this exact instruction remains
            // valid even if conservative indirect-CFG merging marks incoming
            // definitions as conflicting.
            if (candidatePc == targetPc)
            {
                return true;
            }

            if (!_scalarDefinitionsBeforePc.TryGetValue(candidatePc, out var candidate) ||
                !_scalarDefinitionsBeforePc.TryGetValue(targetPc, out var target))
            {
                return false;
            }
'@
Replace-OnceRequired $translator $old $new 'candidatePc == targetPc' 'same-pc-binding-identity'

$old = @'
                if (instruction.Opcode is "SSetpcB64" or "SSwappcB64")
                {
                    break;
                }
'@
$new = @'
                if (instruction.Opcode is "SSetpcB64" or "SSwappcB64")
                {
                    // V76.0.6.1: follow statically-resolved S_SETPC/S_SWAPPC
                    // calls and returns during scalar/resource discovery. If
                    // the target depends on runtime data, keep the historical
                    // conservative behavior and stop this path without failing
                    // shader evaluation.
                    // Evaluate the jump source before S_SWAPPC writes its
                    // return pair. Source and destination may overlap.
                    ulong targetAddress = 0;
                    var hasResolvedTarget = instruction.Sources.Count != 0 &&
                        TryEvaluateScalarOperand64(
                            instruction.Sources[0],
                            scalarRegisters,
                            execMask,
                            out targetAddress);

                    if (instruction.Opcode == "SSwappcB64")
                    {
                        if (instruction.Destinations.Count != 1 ||
                            instruction.Destinations[0] is not
                            {
                                Kind: Gen5OperandKind.ScalarRegister,
                                Value: < ScalarRegisterCount - 1,
                            } returnDestination)
                        {
                            error = $"scalar-swappc-destination pc=0x{instruction.Pc:X}";
                            return false;
                        }

                        var returnAddress = state.Program.Address +
                            instruction.Pc +
                            (ulong)(instruction.Words.Count * sizeof(uint));
                        WriteScalarPair(
                            scalarRegisters,
                            returnDestination.Value,
                            returnAddress,
                            ref execMask);
                    }

                    if (hasResolvedTarget)
                    {
                        targetAddress &= 0xFFFF_FFFF_FFFF_FFFCUL;
                        if (targetAddress >= state.Program.Address)
                        {
                            var targetOffset = targetAddress - state.Program.Address;
                            if (targetOffset <= uint.MaxValue)
                            {
                                var indirectTargetPc = (uint)targetOffset;
                                if (state.Program.Instructions.Any(
                                        candidate => candidate.Pc == indirectTargetPc))
                                {
                                    QueuePath(
                                        indirectTargetPc,
                                        scalarScratchV1179.CloneRegisters(scalarRegisters),
                                        execMask,
                                        scalarConditionCode,
                                        path.Supplemental);
                                }
                            }
                        }
                    }
                    break;
                }
'@
Replace-OnceRequired $evaluator $old $new 'V76.0.6.1: follow statically-resolved S_SETPC/S_SWAPPC' 'scalar-evaluator-indirect-control-buildfix'

$old = '        if (instruction.Opcode is "SLshlB64" or "SLshrB64")'
$new = '        if (instruction.Opcode is "SLshlB64" or "SLshrB64" or "SAshrI64")'
Replace-OnceRequired $evaluator $old $new 'instruction.Opcode is "SLshlB64" or "SLshrB64" or "SAshrI64"' 'scalar-evaluator-ashr-i64-classify'

$old = @'
            value = instruction.Opcode == "SLshlB64"
                ? value << ((int)shift & 63)
                : value >> ((int)shift & 63);
'@
$new = @'
            var shiftAmount = (int)shift & 63;
            value = instruction.Opcode switch
            {
                "SLshlB64" => value << shiftAmount,
                "SLshrB64" => value >> shiftAmount,
                "SAshrI64" => unchecked((ulong)((long)value >> shiftAmount)),
                _ => value,
            };
'@
Replace-OnceRequired $evaluator $old $new '"SAshrI64" => unchecked' 'scalar-evaluator-ashr-i64-semantics'
