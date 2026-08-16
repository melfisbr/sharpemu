$ErrorActionPreference="Stop"

$kernel=@'
    private static string _applicationTitleId = "UNKNOWN";
    public static bool IsReadOnlyGuestMutationPath(string guestPath)
    {
        if (_writableApp0)
        {
            return false;
        }

        var normalized = NormalizeGuestStatCachePath(guestPath);
        return normalized is not null &&
               (string.Equals(normalized, "/app0", StringComparison.OrdinalIgnoreCase) ||
                normalized.StartsWith("/app0/", StringComparison.OrdinalIgnoreCase));
    }
'@
if(-not $kernel.Contains('private static string _applicationTitleId = "UNKNOWN";')) { throw "offline kernel title anchor failed" }
if(-not $kernel.Contains('var normalized = NormalizeGuestStatCachePath(guestPath);')) { throw "offline kernel path anchor failed" }

$ngs=@'
        if (outputAddress == 0 || !outputReadable)
        {
            return SetReturn(ctx, OrbisNgs2ErrorInvalidOutAddress);
        }

        return SetReturn(ctx, unchecked((int)0x80020016));
'@
$old='        return SetReturn(ctx, unchecked((int)0x80020016));'
if(([regex]::Matches($ngs,[regex]::Escape($old))).Count -ne 1) { throw "offline NGS2 anchor count failed" }

$csv=Import-Csv -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "data\DBFZ_EBOOT_IMPORT_AUDIT.csv")
if($csv.Count -ne 2766) { throw "offline eboot inventory row count=$($csv.Count)" }
$critical=@('hyVLT2VlOYk','gEpBkcwxUjw','1-LFLmRFxxM','1G3lF1Gg1k8','n3kSX62fgNo','FzQS6DREDfk')
foreach($nid in $critical) {
    if(-not ($csv.NID -contains $nid)) { throw "critical NID missing from inventory: $nid" }
}
Write-Host "[DBFZ-AUDIT-1814] OFFLINE STRUCTURAL/AUDIT REGRESSION PASSED."
