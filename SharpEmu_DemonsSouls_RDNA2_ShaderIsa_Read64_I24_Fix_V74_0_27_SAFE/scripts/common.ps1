Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRootV74027 {
    param([string]$RepositoryRoot = "")
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Get-Location).Path }
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $markerPath = [System.IO.Path]::Combine($repoRoot, "src", "SharpEmu.CLI", "SharpEmu.CLI.csproj")
    if (-not [System.IO.File]::Exists($markerPath)) { throw "[V74.0.27] Repository root invalid: $repoRoot" }
    return $repoRoot
}

function Get-AgcPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Agc","AgcExports.cs") }
function Get-PresenterPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs") }
function Get-CpuPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","CpuDispatcher.cs") }
function Get-DirectPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.cs") }
function Get-KernelPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Kernel","KernelExports.cs") }
function Get-HostMoviePathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs") }

function Test-V21AbiAppliedV74027 {
    param([string]$Root)
    $cpuPath=Get-CpuPathV74027 -Root $Root
    $directPath=Get-DirectPathV74027 -Root $Root
    $kernelPath=Get-KernelPathV74027 -Root $Root
    foreach ($requiredPath in @($cpuPath,$directPath,$kernelPath)) { if (-not [System.IO.File]::Exists($requiredPath)) { return $false } }
    $cpuText=[System.IO.File]::ReadAllText($cpuPath)
    $directText=[System.IO.File]::ReadAllText($directPath)
    $kernelText=[System.IO.File]::ReadAllText($kernelPath)
    return $cpuText.Contains("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI") -and
        $cpuText.Contains("const ulong entryParamsSize = 0x118;") -and
        $cpuText.Contains("const int maxArguments = 33;") -and
        $directText.Contains("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE") -and
        $kernelText.Contains("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC")
}

function Test-PresenterRollupV74027 {
    param([string]$Root)
    $path=Get-PresenterPathV74027 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_V74_0_23_1_LARGE_ARRAY_SPARSE_BASELINE") -and
        $text.Contains("SHARPEMU_V74_0_24_FRESH_STALE_SOURCE") -and
        $text.Contains("TryRefreshStaleTextureSourceV74024")
}

function Test-V25AppliedV74027 {
    param([string]$Root)
    $path=Get-AgcPathV74027 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION") -and
        $text.Contains("SHARPEMU_WRITE_DATA_PACKET_POSITION") -and
        $text.Contains("packetPositionWriteV74025") -and
        $text.Contains("[V74.0.25][WAIT_RESUME]")
}

function Test-HostLaneSupportV74027 {
    param([string]$Root)
    $path=Get-DirectPathV74027 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_RESERVED_HOST_LANES") -and
        $text.Contains("MapGuestCpuAcrossSmtLanes") -and
        $text.Contains("Environment.ProcessorCount * 3 / 8") -and
        $text.Contains("Demon's Souls' job pool runs ~90% busy")
}

function Invoke-DotNetCheckedV74027 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) { throw "[V74.0.27] dotnet failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Sync-ReleaseRuntimeAssetsV74027 {
    param([string]$Root)
    $debugRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Debug","net10.0","win-x64")
    $releaseRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Release","net10.0","win-x64")
    if (-not [System.IO.Directory]::Exists($releaseRoot)) { return }
    foreach ($assetName in @("plugins","pipeline_cache")) {
        $sourcePath=[System.IO.Path]::Combine($debugRoot,$assetName)
        $destinationPath=[System.IO.Path]::Combine($releaseRoot,$assetName)
        if ([System.IO.Directory]::Exists($sourcePath)) {
            if (-not [System.IO.Directory]::Exists($destinationPath)) { [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null }
            Copy-Item -Path ([System.IO.Path]::Combine($sourcePath,"*")) -Destination $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV74027 {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "" }
    for ($attemptIndex=0;$attemptIndex -lt 5;$attemptIndex++) {
        try {
            $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try {
                $reader=[System.IO.StreamReader]::new($stream,[System.Text.Encoding]::UTF8,$true,65536,$false)
                try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    return ""
}

function Get-DescendantProcessIdsV74027 {
    param([int]$ParentId)
    $result=New-Object 'System.Collections.Generic.List[int]'
    $queue=New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while ($queue.Count -gt 0) {
        $currentId=$queue.Dequeue()
        $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach ($childProcess in $children) {
            $childId=[int]$childProcess.ProcessId
            if (-not $result.Contains($childId)) { $result.Add($childId); $queue.Enqueue($childId) }
        }
    }
    return @($result)
}

function Get-MaxCounterV74027 {
    param([string]$Text,[string]$Pattern)
    $maxValue=0
    foreach($counterMatch in [regex]::Matches($Text,$Pattern)) {
        [int]$parsedValue=0
        if([int]::TryParse($counterMatch.Groups[1].Value,[ref]$parsedValue) -and $parsedValue -gt $maxValue) { $maxValue=$parsedValue }
    }
    return $maxValue
}

function Convert-InvariantDoubleV74027 {
    param([string]$Value)
    [double]$parsed=0
    $normalized=$Value.Replace(",",".")
    if ([double]::TryParse($normalized,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)) { return $parsed }
    return 0.0
}

function Get-HostCpuForGuestV74027 {
    param([int]$GuestCpu,[int]$ProcessorCount,[int]$ReservedLanes)
    $usableLanes=[Math]::Max($ProcessorCount-$ReservedLanes,2)
    $physicalCores=[Math]::Floor($usableLanes/2)
    $lane=$GuestCpu % $usableLanes
    if ($lane -lt $physicalCores) { return $lane*2 }
    return (($lane-$physicalCores)*2)+1
}


function Get-ShaderTranslatorPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.ShaderCompiler","Gen5ShaderTranslator.cs") }
function Get-SpirvTranslatorPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.ShaderCompiler.Vulkan","Gen5SpirvTranslator.cs") }
function Get-SpirvAluPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.ShaderCompiler.Vulkan","Gen5SpirvTranslator.Alu.cs") }
function Get-MslTranslatorPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.ShaderCompiler.Metal","Gen5MslTranslator.cs") }
function Get-MslAluPathV74027 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.ShaderCompiler.Metal","Gen5MslTranslator.Alu.cs") }

function Get-NewLineV74027 {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Replace-UniqueTextV74027 {
    param([string]$Text,[string]$OldText,[string]$NewText,[string]$Label)
    $occurrences=([regex]::Matches($Text,[regex]::Escape($OldText))).Count
    if($occurrences -ne 1){throw "[V74.0.27] Transformer anchor '$Label' count=$occurrences; expected exactly 1."}
    return $Text.Replace($OldText,$NewText)
}

function Convert-ShaderTranslatorV74027 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_27_RDNA2_SHADER_ISA")){return $Text}
    $nl=Get-NewLineV74027 -Text $Text
    $Text=Replace-UniqueTextV74027 -Text $Text -Label "vop2-i24-decode" `
        -OldText '            0x08 => "VMulF32",' `
        -NewText (@(
            '            0x08 => "VMulF32",',
            '            // SHARPEMU_V74_0_27_RDNA2_SHADER_ISA',
            '            // LLVM AMDGPU GFX10 encodes signed 24-bit VOP2 multiplies at 0x09/0x0A.',
            '            0x09 => "VMulI32I24",',
            '            0x0A => "VMulHiI32I24",'
        ) -join $nl)
    $Text=Replace-UniqueTextV74027 -Text $Text -Label "ds-read64-decode" `
        -OldText '            0x4D => "DsWriteB64",' `
        -NewText (@(
            '            0x4D => "DsWriteB64",',
            '            // GFX10/RDNA2 64-bit LDS read family.',
            '            0x76 => "DsReadB64",',
            '            0x77 => "DsRead2B64",',
            '            0x78 => "DsRead2St64B64",'
        ) -join $nl)
    $Text=Replace-UniqueTextV74027 -Text $Text -Label "ds-read64-dest" `
        -OldText '                    "DsRead2B32" or "DsRead2St64B32" => [' `
        -NewText ((@(
            '                    "DsReadB64" => [',
            '                        Gen5Operand.Vector(vectorDestination),',
            '                        Gen5Operand.Vector(vectorDestination + 1),',
            '                    ],',
            '                    "DsRead2B32" or "DsRead2St64B32" => ['
        ) -join $nl))
    $Text=Replace-UniqueTextV74027 -Text $Text -Label "ds-read2-b64-dest" `
        -OldText '                    "DsReadB96" => [' `
        -NewText ((@(
            '                    "DsRead2B64" or "DsRead2St64B64" => [',
            '                        Gen5Operand.Vector(vectorDestination),',
            '                        Gen5Operand.Vector(vectorDestination + 1),',
            '                        Gen5Operand.Vector(vectorDestination + 2),',
            '                        Gen5Operand.Vector(vectorDestination + 3),',
            '                    ],',
            '                    "DsReadB96" => ['
        ) -join $nl))
    return $Text
}

function Convert-SpirvAluV74027 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_27_VOP2_I24_SPIRV")){return $Text}
    $nl=Get-NewLineV74027 -Text $Text
    $block=@(
        '                // SHARPEMU_V74_0_27_VOP2_I24_SPIRV',
        '                case "VMulI32I24":',
        '                {',
        '                    var left = ShiftRightArithmetic(',
        '                        ShiftLeftLogical(GetRawSource(instruction, 0), UInt(8)),',
        '                        UInt(8));',
        '                    var right = ShiftRightArithmetic(',
        '                        ShiftLeftLogical(GetRawSource(instruction, 1), UInt(8)),',
        '                        UInt(8));',
        '                    result = _module.AddInstruction(SpirvOp.IMul, _uintType, left, right);',
        '                    break;',
        '                }',
        '                case "VMulHiI32I24":',
        '                {',
        '                    var left32 = ShiftRightArithmetic(',
        '                        ShiftLeftLogical(GetRawSource(instruction, 0), UInt(8)),',
        '                        UInt(8));',
        '                    var right32 = ShiftRightArithmetic(',
        '                        ShiftLeftLogical(GetRawSource(instruction, 1), UInt(8)),',
        '                        UInt(8));',
        '                    var wideLeft = _module.AddInstruction(',
        '                        SpirvOp.SConvert, _longType, Bitcast(_intType, left32));',
        '                    var wideRight = _module.AddInstruction(',
        '                        SpirvOp.SConvert, _longType, Bitcast(_intType, right32));',
        '                    var product = _module.AddInstruction(',
        '                        SpirvOp.IMul, _longType, wideLeft, wideRight);',
        '                    result = Bitcast(',
        '                        _uintType,',
        '                        _module.AddInstruction(',
        '                            SpirvOp.SConvert,',
        '                            _intType,',
        '                            _module.AddInstruction(',
        '                                SpirvOp.ShiftRightArithmetic,',
        '                                _longType,',
        '                                product,',
        '                                _module.Constant64(_longType, 32))));',
        '                    break;',
        '                }',
        '                case "VMulU32U24":'
    ) -join $nl
    return Replace-UniqueTextV74027 -Text $Text -OldText '                case "VMulU32U24":' -NewText $block -Label "spirv-vop2-i24"
}

function Convert-SpirvTranslatorV74027 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_27_DS_READ64_SPIRV")){return $Text}
    $nl=Get-NewLineV74027 -Text $Text
    $read64=@(
        '                // SHARPEMU_V74_0_27_DS_READ64_SPIRV',
        '                case "DsReadB64":',
        '                {',
        '                    if (instruction.Destinations.Count < 2 || instruction.Sources.Count < 1)',
        '                    {',
        '                        error = "missing LDS read64 operand";',
        '                        return false;',
        '                    }',
        '',
        '                    var address = GetRawSource(instruction, 0);',
        '                    var offset = control.Offset0 | (control.Offset1 << 8);',
        '                    for (var dword = 0; dword < 2; dword++)',
        '                    {',
        '                        var value = Load(',
        '                            _uintType,',
        '                            LdsPointer(address, offset + (uint)(dword * sizeof(uint))));',
        '                        StoreV(instruction.Destinations[dword].Value, value);',
        '                    }',
        '',
        '                    return true;',
        '                }',
        '                case "DsReadB96":'
    ) -join $nl
    $Text=Replace-UniqueTextV74027 -Text $Text -OldText '                case "DsReadB96":' -NewText $read64 -Label "spirv-ds-read64"
    $read2=@(
        '                case "DsRead2B64":',
        '                case "DsRead2St64B64":',
        '                {',
        '                    if (instruction.Destinations.Count < 4 || instruction.Sources.Count < 1)',
        '                    {',
        '                        error = "missing LDS read2-b64 operand";',
        '                        return false;',
        '                    }',
        '',
        '                    var st64 = instruction.Opcode == "DsRead2St64B64";',
        '                    var address = GetRawSource(instruction, 0);',
        '                    var firstOffset = EffectiveDsPair64OffsetBytes(control.Offset0, st64);',
        '                    var secondOffset = EffectiveDsPair64OffsetBytes(control.Offset1, st64);',
        '                    for (var dword = 0; dword < 2; dword++)',
        '                    {',
        '                        var byteDelta = (uint)(dword * sizeof(uint));',
        '                        var first = Load(_uintType, LdsPointer(address, firstOffset + byteDelta));',
        '                        var second = Load(_uintType, LdsPointer(address, secondOffset + byteDelta));',
        '                        StoreV(instruction.Destinations[dword].Value, first);',
        '                        StoreV(instruction.Destinations[dword + 2].Value, second);',
        '                    }',
        '',
        '                    return true;',
        '                }',
        '                case "DsRead2B32":'
    ) -join $nl
    $Text=Replace-UniqueTextV74027 -Text $Text -OldText '                case "DsRead2B32":' -NewText $read2 -Label "spirv-ds-read2-b64"
    $oldHelper=@(
        '        private static uint EffectiveDsPairOffsetBytes(uint offset, bool st64 = false) =>',
        '            offset * (st64 ? 256u : sizeof(uint));'
    ) -join $nl
    $newHelper=@(
        '        private static uint EffectiveDsPairOffsetBytes(uint offset, bool st64 = false) =>',
        '            offset * (st64 ? 256u : sizeof(uint));',
        '',
        '        // 64-bit pair offsets use 8-byte elements; ST64 strides 64 such elements.',
        '        private static uint EffectiveDsPair64OffsetBytes(uint offset, bool st64) =>',
        '            offset * (st64 ? 512u : 2u * sizeof(uint));'
    ) -join $nl
    return Replace-UniqueTextV74027 -Text $Text -OldText $oldHelper -NewText $newHelper -Label "spirv-ds-read64-offset"
}

function Convert-MslAluV74027 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_27_VOP2_I24_MSL")){return $Text}
    $nl=Get-NewLineV74027 -Text $Text
    $block=@(
        '                // SHARPEMU_V74_0_27_VOP2_I24_MSL',
        '                "VMulI32I24" =>',
        '                    $"((uint)(as_type<int>(({RawSource(instruction, 0)}) << 8u) >> 8) * (uint)(as_type<int>(({RawSource(instruction, 1)}) << 8u) >> 8))",',
        '                "VMulHiI32I24" =>',
        '                    AsUInt($"mulhi((as_type<int>(({RawSource(instruction, 0)}) << 8u) >> 8), (as_type<int>(({RawSource(instruction, 1)}) << 8u) >> 8))"),',
        '                "VMulHiU32" =>'
    ) -join $nl
    return Replace-UniqueTextV74027 -Text $Text -OldText '                "VMulHiU32" =>' -NewText $block -Label "msl-vop2-i24"
}

function Convert-MslTranslatorV74027 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_27_DS_READ64_MSL")){return $Text}
    $nl=Get-NewLineV74027 -Text $Text
    $read64=@(
        '                // SHARPEMU_V74_0_27_DS_READ64_MSL',
        '                case "DsReadB64":',
        '                {',
        '                    if (instruction.Destinations.Count < 2)',
        '                    {',
        '                        error = "missing LDS read64 operand";',
        '                        return false;',
        '                    }',
        '',
        '                    var address = Temp("uint", RawSource(instruction, 0));',
        '                    var offset = control.Offset0 | (control.Offset1 << 8);',
        '                    for (var dword = 0; dword < 2; dword++)',
        '                    {',
        '                        StoreVector(',
        '                            instruction.Destinations[dword].Value,',
        '                            $"sharpemu_lds[{LdsIndex(address, offset + (uint)(dword * sizeof(uint)))}]");',
        '                    }',
        '',
        '                    return true;',
        '                }',
        '                case "DsReadB96":'
    ) -join $nl
    $Text=Replace-UniqueTextV74027 -Text $Text -OldText '                case "DsReadB96":' -NewText $read64 -Label "msl-ds-read64"
    $read2=@(
        '                case "DsRead2B64":',
        '                case "DsRead2St64B64":',
        '                {',
        '                    if (instruction.Destinations.Count < 4)',
        '                    {',
        '                        error = "missing LDS read2-b64 operand";',
        '                        return false;',
        '                    }',
        '',
        '                    var st64 = instruction.Opcode == "DsRead2St64B64";',
        '                    var address = Temp("uint", RawSource(instruction, 0));',
        '                    var firstOffset = EffectiveDsPair64OffsetBytes(control.Offset0, st64);',
        '                    var secondOffset = EffectiveDsPair64OffsetBytes(control.Offset1, st64);',
        '                    for (var dword = 0; dword < 2; dword++)',
        '                    {',
        '                        var byteDelta = (uint)(dword * sizeof(uint));',
        '                        StoreVector(instruction.Destinations[dword].Value,',
        '                            $"sharpemu_lds[{LdsIndex(address, firstOffset + byteDelta)}]");',
        '                        StoreVector(instruction.Destinations[dword + 2].Value,',
        '                            $"sharpemu_lds[{LdsIndex(address, secondOffset + byteDelta)}]");',
        '                    }',
        '',
        '                    return true;',
        '                }',
        '                case "DsRead2B32":'
    ) -join $nl
    $Text=Replace-UniqueTextV74027 -Text $Text -OldText '                case "DsRead2B32":' -NewText $read2 -Label "msl-ds-read2-b64"
    $oldHelper=@(
        '        private static uint EffectiveDsPairOffsetBytes(uint offset, bool st64) =>',
        '            offset * (st64 ? 256u : sizeof(uint));'
    ) -join $nl
    $newHelper=@(
        '        private static uint EffectiveDsPairOffsetBytes(uint offset, bool st64) =>',
        '            offset * (st64 ? 256u : sizeof(uint));',
        '',
        '        private static uint EffectiveDsPair64OffsetBytes(uint offset, bool st64) =>',
        '            offset * (st64 ? 512u : 2u * sizeof(uint));'
    ) -join $nl
    return Replace-UniqueTextV74027 -Text $Text -OldText $oldHelper -NewText $newHelper -Label "msl-ds-read64-offset"
}

function Get-ShaderIsaStateV74027 {
    param([string]$Root)
    $paths=@(
        (Get-ShaderTranslatorPathV74027 -Root $Root),
        (Get-SpirvTranslatorPathV74027 -Root $Root),
        (Get-SpirvAluPathV74027 -Root $Root),
        (Get-MslTranslatorPathV74027 -Root $Root),
        (Get-MslAluPathV74027 -Root $Root)
    )
    foreach($sourcePath in $paths){if(-not [System.IO.File]::Exists($sourcePath)){return "Missing"}}
    $core=[System.IO.File]::ReadAllText($paths[0])
    $spirv=[System.IO.File]::ReadAllText($paths[1])
    $spirvAlu=[System.IO.File]::ReadAllText($paths[2])
    $msl=[System.IO.File]::ReadAllText($paths[3])
    $mslAlu=[System.IO.File]::ReadAllText($paths[4])
    $applied=$core.Contains("SHARPEMU_V74_0_27_RDNA2_SHADER_ISA") -and
        $core.Contains('0x76 => "DsReadB64"') -and $core.Contains('0x77 => "DsRead2B64"') -and
        $core.Contains('0x09 => "VMulI32I24"') -and
        $spirv.Contains("SHARPEMU_V74_0_27_DS_READ64_SPIRV") -and
        $spirvAlu.Contains("SHARPEMU_V74_0_27_VOP2_I24_SPIRV") -and
        $msl.Contains("SHARPEMU_V74_0_27_DS_READ64_MSL") -and
        $mslAlu.Contains("SHARPEMU_V74_0_27_VOP2_I24_MSL")
    if($applied){return "Applied"}
    if($core.Contains("SHARPEMU_V74_0_27_RDNA2_SHADER_ISA") -or $spirv.Contains("SHARPEMU_V74_0_27_DS_READ64_SPIRV") -or $spirvAlu.Contains("SHARPEMU_V74_0_27_VOP2_I24_SPIRV") -or $msl.Contains("SHARPEMU_V74_0_27_DS_READ64_MSL") -or $mslAlu.Contains("SHARPEMU_V74_0_27_VOP2_I24_MSL")){return "Partial"}
    return "Baseline"
}
