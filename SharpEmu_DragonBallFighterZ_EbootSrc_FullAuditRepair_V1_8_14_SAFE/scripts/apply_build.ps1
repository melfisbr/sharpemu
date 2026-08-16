. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kernelText=Get-Content -LiteralPath $kernel -Raw
$ngsText=Get-Content -LiteralPath $ngs -Raw

$backupDir=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_FullAuditRepair_V1_8_14_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $kernel -Destination (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Force
Copy-Item -LiteralPath $ngs -Destination (Join-Path $backupDir "Ngs2Exports.cs") -Force

try {
    if(-not $kernelText.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14')) {
        $field='    private static string _applicationTitleId = "UNKNOWN";'
        if(([regex]::Matches($kernelText,[regex]::Escape($field))).Count -ne 1) { throw "Kernel title field anchor count mismatch." }
        $fieldPatch=@'
    private static string _applicationTitleId = "UNKNOWN";

    // SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14
    internal static string CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId);
'@
        $kernelText=$kernelText.Replace($field,$fieldPatch)

        $norm='        var normalized = NormalizeGuestStatCachePath(guestPath);'
        if(([regex]::Matches($kernelText,[regex]::Escape($norm))).Count -lt 1) { throw "Kernel normalized-path anchor not found." }
        $policy=@'
        var normalized = NormalizeGuestStatCachePath(guestPath);

        // SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14
        // DBFZ PPSA09790 is an unpackaged UE build that writes its Saved tree
        // below app0. Keep retail app0 read-only for every other title/path.
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
        $kernelText=$kernelText.Replace($norm,$policy)
        Set-Content -LiteralPath $kernel -Value $kernelText -Encoding utf8
        Write-Host "[DBFZ-AUDIT-1814] DBFZ Saved/app0 compatibility installed."
    }

    $ngsText=Get-Content -LiteralPath $ngs -Raw
    if(-not $ngsText.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14')) {
        $old='        return SetReturn(ctx, unchecked((int)0x80020016));'
        if(([regex]::Matches($ngsText,[regex]::Escape($old))).Count -ne 1) { throw "NGS2 return anchor count mismatch." }
        $new=@'
        // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14
        // Runtime evidence shows consecutive DBFZ output records at a 0x240-byte
        // stride. Restrict compatibility to PPSA09790; other titles retain the
        // explicit INVALID_ARGUMENT path until their ABI is proven.
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
                    $"[DBFZ-NGS2-1814][PARSE_OK] call={call} out=0x{outputAddress:X16} bytes=0x240");
            }

            return SetReturn(ctx, 0);
        }

        return SetReturn(ctx, unchecked((int)0x80020016));
'@
        $ngsText=$ngsText.Replace($old,$new)
        Set-Content -LiteralPath $ngs -Value $ngsText -Encoding utf8
        Write-Host "[DBFZ-AUDIT-1814] DBFZ NGS2 ParseWaveform compatibility installed."
    }

    Push-Location $repo
    try {
        dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
} catch {
    Copy-Item -LiteralPath (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Destination $kernel -Force
    Copy-Item -LiteralPath (Join-Path $backupDir "Ngs2Exports.cs") -Destination $ngs -Force
    Write-Host "[DBFZ-AUDIT-1814] Source restored after patch/build failure."
    throw
}

Write-Host "[DBFZ-AUDIT-1814] BUILD PASSED. Backup: $backupDir"
