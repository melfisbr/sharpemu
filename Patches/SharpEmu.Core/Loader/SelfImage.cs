// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Core.Memory;

namespace SharpEmu.Core.Loader;

public sealed class SelfImage
{
    private readonly ulong _imageBase;

    public SelfImage(
        bool isSelf,
        ElfHeader elfHeader,
        IReadOnlyList<ProgramHeader> programHeaders,
        IReadOnlyList<VirtualMemoryRegion> mappedRegions,
        IReadOnlyDictionary<ulong, string>? importStubs = null,
        IReadOnlyDictionary<string, ulong>? runtimeSymbols = null,
        IReadOnlyList<ImportedSymbolRelocation>? importedRelocations = null,
        IReadOnlyList<ulong>? preInitializerFunctions = null,
        IReadOnlyList<ulong>? initializerFunctions = null,
        IReadOnlyList<string>? neededModuleNames = null,
        ulong initFunctionEntryPoint = 0,
        ulong imageBase = 0,
        ulong procParamAddress = 0,
        ulong moduleParamAddress = 0,
        string? title = null,
        string? titleId = null,
        string? version = null,
        uint tlsModuleId = 0,
        ulong tlsMemorySize = 0,
        ulong tlsStaticOffset = 0)
    {
        ArgumentNullException.ThrowIfNull(programHeaders);
        ArgumentNullException.ThrowIfNull(mappedRegions);

        IsSelf = isSelf;
        ElfHeader = elfHeader;
        ProgramHeaders = programHeaders;
        MappedRegions = mappedRegions;
        ImportStubs = importStubs ?? new Dictionary<ulong, string>();
        RuntimeSymbols = runtimeSymbols ?? new Dictionary<string, ulong>(StringComparer.Ordinal);
        ImportedRelocations = importedRelocations ?? Array.Empty<ImportedSymbolRelocation>();
        PreInitializerFunctions = preInitializerFunctions ?? Array.Empty<ulong>();
        InitializerFunctions = initializerFunctions ?? Array.Empty<ulong>();
        NeededModuleNames = neededModuleNames ?? Array.Empty<string>();
        InitFunctionEntryPoint = initFunctionEntryPoint;
        _imageBase = imageBase;
        ProcParamAddress = procParamAddress;
        ModuleParamAddress = moduleParamAddress;
        Title = title;
        TitleId = titleId;
        Version = version;
        TlsModuleId = tlsModuleId;
        TlsMemorySize = tlsMemorySize;
        TlsStaticOffset = tlsStaticOffset;
    }

    public bool IsSelf { get; }

    public ElfHeader ElfHeader { get; }

    public IReadOnlyList<ProgramHeader> ProgramHeaders { get; }

    public IReadOnlyList<VirtualMemoryRegion> MappedRegions { get; }

    public IReadOnlyDictionary<ulong, string> ImportStubs { get; }

    public IReadOnlyDictionary<string, ulong> RuntimeSymbols { get; }

    public IReadOnlyList<ImportedSymbolRelocation> ImportedRelocations { get; }

    public IReadOnlyList<ulong> PreInitializerFunctions { get; }

    public IReadOnlyList<ulong> InitializerFunctions { get; }

    /// <summary>
    /// Dynamic-loader dependency names declared by DT_NEEDED / DT_SCE_NEEDED_MODULE.
    /// The runtime uses these names only for dependency-first initializer ordering;
    /// absence of metadata preserves the stable preload order.
    /// </summary>
    public IReadOnlyList<string> NeededModuleNames { get; }

    public ulong InitFunctionEntryPoint { get; }

    public ulong EntryPoint => ElfHeader.EntryPoint + _imageBase;

    public ulong ProcParamAddress { get; }

    /// <summary>
    /// Address of PT_SCE_MODULE_PARAM (0x61000002), when the image exposes one.
    /// Kept separate from ProcParamAddress because the two program-header types
    /// have distinct roles in SCE ELF layouts.
    /// </summary>
    public ulong ModuleParamAddress { get; }

    public string? Title { get; }

    public string? TitleId { get; }

    public string? Version { get; }

    public uint TlsModuleId { get; }

    public ulong TlsMemorySize { get; }

    /// <summary>Variant II distance from the thread pointer to this module's static TLS base.</summary>
    public ulong TlsStaticOffset { get; }
}
