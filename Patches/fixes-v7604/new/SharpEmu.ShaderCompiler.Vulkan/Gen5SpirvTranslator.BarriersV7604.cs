// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.4: broaden barrier emission for graphics stages and wave sync.

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        /// <summary>
        /// Emits the strongest barrier representable for the current stage.
        /// Compute: workgroup ControlBarrier. Graphics: MemoryBarrier + subgroup.
        /// </summary>
        private void EmitStageBarrierV7604()
        {
            if (_stage == Gen5SpirvStage.Compute)
            {
                var workgroup = UInt(2); // ScopeWorkgroup
                var semantics = UInt(0x108); // AcquireRelease | WorkgroupMemory
                _module.AddStatement(
                    SpirvOp.ControlBarrier,
                    workgroup,
                    workgroup,
                    semantics);
                return;
            }

            // Graphics: memory barrier at device scope + subgroup barrier when
            // wave ops are in use. Avoid illegal workgroup barriers in VS/PS.
            var device = UInt(1); // ScopeDevice
            var memSemantics = UInt(0x48); // AcquireRelease | UniformMemory
            _module.AddStatement(SpirvOp.MemoryBarrier, device, memSemantics);

            if (_usesSubgroupOperations || _usesWaveControl)
            {
                var subgroup = UInt(3); // ScopeSubgroup
                var subSem = UInt(0x48);
                _module.AddStatement(
                    SpirvOp.ControlBarrier,
                    subgroup,
                    subgroup,
                    subSem);
            }
        }
    }
}
