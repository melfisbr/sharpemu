. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kernelText=Get-Content -LiteralPath $kernel -Raw
$ngsText=Get-Content -LiteralPath $ngs -Raw

$backupDir=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_FullAuditRepair_V1_8_14_1_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $kernel -Destination (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Force
Copy-Item -LiteralPath $ngs -Destination (Join-Path $backupDir "Ngs2Exports.cs") -Force

try {
    # Kernel: expose current title exactly once.
    if(-not $kernelText.Contains('CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId)')) {
        $field='    private static string _applicationTitleId = "UNKNOWN";'
        $fieldIndex=$kernelText.IndexOf($field,[StringComparison]::Ordinal)
        if($fieldIndex -lt 0) { throw "Kernel title field anchor not found." }
        $fieldEnd=$fieldIndex+$field.Length
        $bridge=@'

    internal static string CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId);
'@
        $kernelText=$kernelText.Insert($fieldEnd,$bridge)
    }

    # Kernel: insert DBFZ Saved policy only inside IsReadOnlyGuestMutationPath.
    if(-not $kernelText.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_1') -and
       -not $kernelText.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14')) {
        $methodToken='public static bool IsReadOnlyGuestMutationPath(string guestPath)'
        $methodIndex=$kernelText.IndexOf($methodToken,[StringComparison]::Ordinal)
        if($methodIndex -lt 0) { throw "Kernel IsReadOnlyGuestMutationPath method not found." }

        $norm='        var normalized = NormalizeGuestStatCachePath(guestPath);'
        $normIndex=$kernelText.IndexOf($norm,$methodIndex,[StringComparison]::Ordinal)
        if($normIndex -lt 0) { throw "Kernel normalized path line not found in read-only policy method." }
        $lineEnd=$kernelText.IndexOf("`n",$normIndex)
        if($lineEnd -lt 0) { throw "Kernel normalized path line terminator not found." }

        $policy=@'

        // SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_1
        // DBFZ PPSA09790 is an unpackaged UE build that writes its Saved tree
        // below app0. Keep every other app0 path/title read-only.
        if (string.Equals(
                Volatile.Read(ref _applicationTitleId),
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase) &&
            normalized is not null &&
            (string.Equals(normalized, "/app0/red/saved", StringComparison.OrdinalIgnoreCase) ||
             normalized.StartsWith("/app0/red/saved/", StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }
'@
        $kernelText=$kernelText.Insert($lineEnd+1,$policy)
    }
    Set-Content -LiteralPath $kernel -Value $kernelText -Encoding utf8

    # NGS2: patch the V1.8.13 method structurally, regardless of the exact
    # spelling of its current final error return.
    $ngsText=Get-Content -LiteralPath $ngs -Raw
    if(-not $ngsText.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_1') -and
       -not $ngsText.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14')) {
        $methodToken='public static int Ngs2ParseWaveformDataV1813(CpuContext ctx)'
        $methodIndex=$ngsText.IndexOf($methodToken,[StringComparison]::Ordinal)
        if($methodIndex -lt 0) { throw "Ngs2ParseWaveformDataV1813 method anchor missing." }

        $tail=$ngsText.Substring($methodIndex)
        $returnRx=[regex]'return\s+SetReturn\(ctx,\s*[^;]+;'
        $matches=$returnRx.Matches($tail)
        if($matches.Count -lt 1) {
            throw "No SetReturn final path found inside/after Ngs2ParseWaveformDataV1813."
        }

        # The probe method is appended at the end of Ngs2Exports; use its last
        # SetReturn as the existing default/fallback path and preserve it.
        $last=$matches[$matches.Count-1]
        $absolute=$methodIndex+$last.Index
        $fallback=$last.Value

        $compat=@'
        // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_1
        // The DBFZ runtime probe observed output records with a 0x240-byte
        // stride. Initialize only that title's record; preserve the existing
        // fallback return for every other title.
        if (string.Equals(
                SharpEmu.Libs.Kernel.KernelMemoryCompatExports.CurrentApplicationTitleId,
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase))
        {
            Span<byte> compatibilityOutput = stackalloc byte[0x240];
            compatibilityOutput.Clear();
            if (!ctx.Memory.TryWrite(outputAddress, compatibilityOutput))
            {
                return SetReturn(ctx, OrbisNgs2ErrorInvalidOutAddress);
            }

            if (shouldDump)
            {
                Console.Error.WriteLine(
                    $"[DBFZ-NGS2-18141][PARSE_OK] call={call} out=0x{outputAddress:X16} bytes=0x240");
            }

            return SetReturn(ctx, 0);
        }

'@
        $ngsText=$ngsText.Insert($absolute,$compat)
        Set-Content -LiteralPath $ngs -Value $ngsText -Encoding utf8
    }

    Push-Location $repo
    try {
        dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
} catch {
    Copy-Item -LiteralPath (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Destination $kernel -Force
    Copy-Item -LiteralPath (Join-Path $backupDir "Ngs2Exports.cs") -Destination $ngs -Force
    Write-Host "[DBFZ-AUDIT-181411] Source restored after patch/build failure."
    throw
}

Write-Host "[DBFZ-AUDIT-181411] BUILD PASSED. Backup: $backupDir"
