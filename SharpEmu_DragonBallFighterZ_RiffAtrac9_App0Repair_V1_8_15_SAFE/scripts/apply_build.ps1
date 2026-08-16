. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$backupDir=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_RiffAtrac9App0_V1_8_15_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
Copy-Item -LiteralPath $ngs -Destination (Join-Path $backupDir "Ngs2Exports.cs") -Force
Copy-Item -LiteralPath $kernel -Destination (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Force

try {
 $nt=Get-Content -LiteralPath $ngs -Raw
 $kt=Get-Content -LiteralPath $kernel -Raw

 if(-not $nt.Contains('SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15')) {
   $startMarker='        // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2'
   $start=$nt.IndexOf($startMarker,[StringComparison]::Ordinal)
   if($start -lt 0){throw "V1.8.14.2 NGS2 compatibility marker not found."}
   $success='            return SetReturn(ctx, 0);'
   $successAt=$nt.IndexOf($success,$start,[StringComparison]::Ordinal)
   if($successAt -lt 0){throw "V1.8.14.2 success return not found."}
   $fallback='        return SetReturn(ctx,'
   $fallbackAt=$nt.IndexOf($fallback,$successAt+$success.Length,[StringComparison]::Ordinal)
   if($fallbackAt -lt 0){throw "Preserved NGS2 fallback not found."}

   $new=@'
        // SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15
        // DBFZ supplies RIFF/WAVE_EXTENSIBLE ATRAC9. The 0x240 output record
        // arrives pre-initialized by the caller; do not clear flags/indices/pointers.
        if (string.Equals(
                SharpEmu.Libs.Kernel.KernelMemoryCompatExports.CurrentApplicationTitleId,
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase))
        {
            Span<byte> riff = stackalloc byte[68];
            if (dataAddress != 0 &&
                dataSize >= 68 &&
                ctx.Memory.TryRead(dataAddress, riff) &&
                riff[0] == (byte)'R' && riff[1] == (byte)'I' &&
                riff[2] == (byte)'F' && riff[3] == (byte)'F' &&
                riff[8] == (byte)'W' && riff[9] == (byte)'A' &&
                riff[10] == (byte)'V' && riff[11] == (byte)'E')
            {
                var formatTag = BinaryPrimitives.ReadUInt16LittleEndian(riff[20..22]);
                var channels = BinaryPrimitives.ReadUInt16LittleEndian(riff[22..24]);
                var sampleRate = BinaryPrimitives.ReadUInt32LittleEndian(riff[24..28]);
                var blockAlign = BinaryPrimitives.ReadUInt16LittleEndian(riff[32..34]);
                var bitsPerSample = BinaryPrimitives.ReadUInt16LittleEndian(riff[34..36]);
                var cbSize = BinaryPrimitives.ReadUInt16LittleEndian(riff[36..38]);

                // ATRAC9 WAVE_EXTENSIBLE SubFormat GUID, little-endian bytes:
                // D2 42 E1 47 BA 36 8D 4D 88 FC 61 65 4F 8C 83 6C
                var atrac9 =
                    formatTag == 0xFFFE &&
                    riff[44] == 0xD2 && riff[45] == 0x42 &&
                    riff[46] == 0xE1 && riff[47] == 0x47 &&
                    riff[48] == 0xBA && riff[49] == 0x36 &&
                    riff[50] == 0x8D && riff[51] == 0x4D &&
                    riff[52] == 0x88 && riff[53] == 0xFC &&
                    riff[54] == 0x61 && riff[55] == 0x65 &&
                    riff[56] == 0x4F && riff[57] == 0x8C &&
                    riff[58] == 0x83 && riff[59] == 0x6C;

                if (shouldDump)
                {
                    Console.Error.WriteLine(
                        $"[DBFZ-NGS2-1815][RIFF] call={call} size=0x{dataSize:X} " +
                        $"fmt=0x{formatTag:X4} ch={channels} rate={sampleRate} " +
                        $"align={blockAlign} bits={bitsPerSample} cb={cbSize} " +
                        $"atrac9={atrac9} out=0x{outputAddress:X16} preserved=1");
                }

                // Preserve the existing descriptor verbatim. Returning success here
                // is non-destructive and matches the caller-initialized structure.
                return SetReturn(ctx, 0);
            }
        }

'@
   $nt=$nt.Remove($start,$fallbackAt-$start).Insert($start,$new)
   Set-Content -LiteralPath $ngs -Value $nt -Encoding utf8
 }

 if(-not $kt.Contains('SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15')) {
   $needle=@'
        if (_writableApp0)
        {
            return false;
        }
'@
   $idx=$kt.IndexOf($needle,[StringComparison]::Ordinal)
   if($idx -lt 0){throw "Kernel writable-app0 policy anchor missing."}
   $insertAt=$idx+$needle.Length
   $block=@'

        // SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15
        // Writable-app0 A/B removed all DBFZ mkdir/open permission failures.
        // Scope this behavior to PPSA09790; every other title retains retail policy.
        if (string.Equals(
                Volatile.Read(ref _applicationTitleId),
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }
'@
   $kt=$kt.Insert($insertAt,$block)
   Set-Content -LiteralPath $kernel -Value $kt -Encoding utf8
 }

 Push-Location $repo
 try {
   dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
   if($LASTEXITCODE -ne 0){throw "dotnet build failed with exit code $LASTEXITCODE"}
 } finally {Pop-Location}
} catch {
 Copy-Item -LiteralPath (Join-Path $backupDir "Ngs2Exports.cs") -Destination $ngs -Force
 Copy-Item -LiteralPath (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Destination $kernel -Force
 Write-Host "[DBFZ-RIFF-1815] Source restored after patch/build failure."
 throw
}
Write-Host "[DBFZ-RIFF-1815] BUILD PASSED. Backup: $backupDir"
