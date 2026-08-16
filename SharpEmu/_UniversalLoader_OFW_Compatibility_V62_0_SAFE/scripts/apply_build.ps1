param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r
$self=Join-Path $r 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$ph=Join-Path $r 'src\SharpEmu.Core\Loader\ProgramHeader.cs'
$s=[IO.File]::ReadAllText($self); $p=[IO.File]::ReadAllText($ph)
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $b=Join-Path $r ".sharpemu-hotfix-backup\UniversalLoader_V62_0_$stamp"
New-Item -ItemType Directory -Force -Path $b|Out-Null
Copy-Item -LiteralPath $self -Destination (Join-Path $b 'SelfLoader.cs')
Copy-Item -LiteralPath $ph -Destination (Join-Path $b 'ProgramHeader.cs')
try {
 if($s.IndexOf('V62.0 UNIVERSAL_LOADER_OFW',[StringComparison]::Ordinal)-lt 0) {
  $old=@'
        if (header.ProgramHeaderEntrySize != ProgramHeaderSize)
        {
            throw new InvalidDataException($"Unsupported ELF program header entry size: {header.ProgramHeaderEntrySize}.");
        }
'@
  $new=@'
        // V62.0 UNIVERSAL_LOADER_OFW
        // ParseProgramHeaders already advances by e_phentsize and reads only
        // the known ELF64 prefix. Accept compatible extended PH records.
        if (header.ProgramHeaderEntrySize < ProgramHeaderSize)
        {
            throw new InvalidDataException(
                $"ELF program header entry size {header.ProgramHeaderEntrySize} is smaller than required ELF64 prefix {ProgramHeaderSize}.");
        }
'@
  if(!$s.Contains($old)){throw 'APPLY ERROR: PH entry-size block not found'}
  $s=$s.Replace($old,$new)

  $old=@'
        if (magic != ElfMagic)
        {
            throw new InvalidDataException(
                $"Image is neither a decrypted ELF nor a recognized fake-signed SELF " +
                $"(leading bytes 0x{magic:X8}). This is almost certainly a still-encrypted " +
                $"retail eboot — SharpEmu has no decryption keys and requires a decrypted / " +
                $"fake-signed (fSELF) image.");
        }
'@
  $new=@'
        if (magic != ElfMagic)
        {
            // V62.0 UNIVERSAL_LOADER_OFW
            // Accept alternate *decrypted* wrappers only when a complete
            // ELF64/x86-64 payload is structurally proven inside the file.
            if (TryFindEmbeddedDecryptedElf(imageData, out var embeddedElfOffset))
            {
                Console.Error.WriteLine(
                    $"[LOADER][COMPAT][V62.0] validated embedded decrypted ELF at file offset 0x{embeddedElfOffset:X}.");
                return new LoadContext(false, embeddedElfOffset, 0, Array.Empty<SelfSegment>());
            }

            throw new InvalidDataException(
                $"Image is neither a decrypted ELF nor a recognized fake-signed SELF " +
                $"(leading bytes 0x{magic:X8}), and no validated embedded ELF64 payload was found. " +
                "Still-encrypted retail eboots must be decrypted before loading.");
        }
'@
  if(!$s.Contains($old)){throw 'APPLY ERROR: unknown-wrapper block not found'}
  $s=$s.Replace($old,$new)

  $helper=@'
    // V62.0 UNIVERSAL_LOADER_OFW
    private static bool TryFindEmbeddedDecryptedElf(ReadOnlySpan<byte> data, out int elfOffset)
    {
        elfOffset = 0;
        const ushort X64 = 62;
        var ehSize = Unsafe.SizeOf<ElfHeader>();
        var max = Math.Min(data.Length - ehSize, 4 * 1024 * 1024);
        if (max < 4) return false;

        for (var candidate = 4; candidate <= max; candidate += 4)
        {
            if (data[candidate] != 0x7F || data[candidate + 1] != (byte)'E' ||
                data[candidate + 2] != (byte)'L' || data[candidate + 3] != (byte)'F')
                continue;

            ElfHeader h;
            try { h = ReadUnmanaged<ElfHeader>(data, candidate); }
            catch { continue; }
            if (!h.HasElfMagic || !h.Is64Bit || !h.IsLittleEndian || h.Machine != X64 ||
                h.ProgramHeaderEntrySize < ProgramHeaderSize || h.ProgramHeaderCount == 0 || h.ProgramHeaderCount > 512)
                continue;

            ulong table, size, end;
            try
            {
                table = checked((ulong)candidate + h.ProgramHeaderOffset);
                size = checked((ulong)h.ProgramHeaderCount * h.ProgramHeaderEntrySize);
                end = checked(table + size);
            }
            catch (OverflowException) { continue; }
            if (end > (ulong)data.Length) continue;

            var hasLoad = false;
            var valid = true;
            for (var i = 0; i < h.ProgramHeaderCount; i++)
            {
                var entry = table + (ulong)i * h.ProgramHeaderEntrySize;
                if (entry > int.MaxValue) { valid = false; break; }
                ProgramHeader ph;
                try { ph = ReadUnmanaged<ProgramHeader>(data, checked((int)entry)); }
                catch { valid = false; break; }
                if (ph.HeaderType != ProgramHeaderType.Load) continue;
                hasLoad = true;
                if (ph.FileSize > ph.MemorySize) { valid = false; break; }
                if (ph.FileSize == 0) continue;
                ulong fileEnd;
                try { fileEnd = checked((ulong)candidate + ph.Offset + ph.FileSize); }
                catch (OverflowException) { valid = false; break; }
                if (fileEnd > (ulong)data.Length) { valid = false; break; }
            }
            if (!valid || !hasLoad) continue;
            elfOffset = candidate;
            return true;
        }
        return false;
    }

'@
  $anchor='    private static ProgramHeader[] ParseProgramHeaders('
  $pos=$s.IndexOf($anchor,[StringComparison]::Ordinal); if($pos-lt 0){throw 'APPLY ERROR: ParseProgramHeaders anchor missing'}
  $s=$s.Insert($pos,$helper)

  # The current loader has a section relocation fallback, but PT_DYNAMIC absence
  # returns before it can run. Route that case to a section-only resolver.
  $old=@'
        if (!TryGetProgramHeader(programHeaders, ProgramHeaderType.Dynamic, out var dynamicHeader, out var dynamicHeaderIndex))
        {
            return EmptyImportStubs;
        }
'@
  $new=@'
        if (!TryGetProgramHeader(programHeaders, ProgramHeaderType.Dynamic, out var dynamicHeader, out var dynamicHeaderIndex))
        {
            Console.Error.WriteLine(
                "[LOADER][COMPAT][V62.0] PT_DYNAMIC absent; trying section relocation/symbol fallback.");
            return ResolveSectionOnlyImports(
                imageData, loadContext, elfHeader, virtualMemory, imageBase,
                moduleManager, tlsModuleId, out importedRelocations);
        }
'@
  if(!$s.Contains($old)){throw 'APPLY ERROR: PT_DYNAMIC early-return block not found'}
  $s=$s.Replace($old,$new)

  $resolver=@'
    // V62.0 UNIVERSAL_LOADER_OFW
    private static IReadOnlyDictionary<ulong, string> ResolveSectionOnlyImports(
        ReadOnlySpan<byte> imageData, LoadContext loadContext, ElfHeader elfHeader,
        IVirtualMemory virtualMemory, ulong imageBase, IModuleManager? moduleManager,
        uint tlsModuleId, out IReadOnlyList<ImportedSymbolRelocation> importedRelocations)
    {
        var descriptors = new List<RelocationDescriptor>(256);
        var orderedNids = new List<string>(128);
        var seenNids = new HashSet<string>(StringComparer.Ordinal);
        var recovered = AppendSectionRelocationDescriptors(
            imageData, loadContext, elfHeader, virtualMemory, imageBase, tlsModuleId,
            descriptors, orderedNids, seenNids);
        Console.Error.WriteLine(
            $"[LOADER][COMPAT][V62.0] section fallback relocations={recovered} nids={orderedNids.Count} descriptors={descriptors.Count}");
        if (descriptors.Count == 0)
        {
            importedRelocations = Array.Empty<ImportedSymbolRelocation>();
            return EmptyImportStubs;
        }

        importedRelocations = BuildImportedRelocations(descriptors);
        var eligible = CollectStubEligibleNids(descriptors, moduleManager);
        var stubNids = orderedNids.Where(eligible.Contains).ToArray();
        var stubs = CreateImportStubMapping(virtualMemory, stubNids);
        var addresses = new Dictionary<string, ulong>(StringComparer.Ordinal);
        foreach (var entry in stubs) addresses[entry.Value] = entry.Key;

        foreach (var descriptor in descriptors)
        {
            ulong symbolValue;
            if (descriptor.ImportNid is null) symbolValue = descriptor.SymbolValue;
            else if (addresses.TryGetValue(descriptor.ImportNid, out var stubAddress)) symbolValue = stubAddress;
            else if (descriptor.IsWeak) symbolValue = 0;
            else continue;

            var targetValue = ComputeRelocationValue(descriptor, symbolValue);
            if (!TryWriteRelocationValue(virtualMemory, descriptor, targetValue, out var error))
                throw new InvalidDataException(
                    $"Failed section-fallback relocation at 0x{descriptor.TargetAddress:X16}: {error}");
        }
        return stubs;
    }

'@
  $anchor='    private static int AppendSectionRelocationDescriptors('
  $pos=$s.IndexOf($anchor,[StringComparison]::Ordinal); if($pos-lt 0){throw 'APPLY ERROR: section resolver anchor missing'}
  $s=$s.Insert($pos,$resolver)
  [IO.File]::WriteAllText($self,$s,[Text.UTF8Encoding]::new($false))

  # Descriptive PH types observed across SCE/GNU ELF families; no new mapping semantics.
  if($p.IndexOf('SceModuleParam = 0x61000002',[StringComparison]::Ordinal)-lt 0){
    $p=$p.Replace('    SceProcParam = 0x61000001,',"    SceProcParam = 0x61000001,`r`n`r`n    SceModuleParam = 0x61000002,")
  }
  if($p.IndexOf('GnuStack = 0x6474E551',[StringComparison]::Ordinal)-lt 0){
    $p=$p.Replace('    GnuEhFrame = 0x6474E550,',"    GnuEhFrame = 0x6474E550,`r`n    GnuStack = 0x6474E551,`r`n    GnuRelro = 0x6474E552,")
  }
  [IO.File]::WriteAllText($ph,$p,[Text.UTF8Encoding]::new($false))
  Write-Host "[V62.0] Loader compatibility changes applied. Backup: $b"
 }

 Push-Location $r
 try {
   & dotnet build '.\src\SharpEmu.Core\SharpEmu.Core.csproj' -c Debug --nologo
   if($LASTEXITCODE-ne 0){throw "SharpEmu.Core build failed: $LASTEXITCODE"}
   & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
   if($LASTEXITCODE-ne 0){throw "SharpEmu.CLI build failed: $LASTEXITCODE"}
 } finally { Pop-Location }
 Write-Host '[V62.0] SUCCESS'
 Write-Host '[V62.0] Decrypted-wrapper acceptance, extended PH records and section-only import fallback enabled.'
}
catch {
 Copy-Item -LiteralPath (Join-Path $b 'SelfLoader.cs') -Destination $self -Force
 Copy-Item -LiteralPath (Join-Path $b 'ProgramHeader.cs') -Destination $ph -Force
 Write-Host '[V62.0] FAILURE: loader sources restored automatically.' -ForegroundColor Yellow
 throw
}
