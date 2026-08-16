$ErrorActionPreference="Stop"

$sample=@'
public static int Ngs2ParseWaveformDataV1813(CpuContext ctx)
{
    if (outputAddress == 0)
    {
        return SetReturn(ctx, OrbisNgs2ErrorInvalidOutAddress);
    }

    if (string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_NGS2_PARSE_COMPAT"), "1", StringComparison.Ordinal))
    {
        return SetReturn(ctx, 0);
    }

    return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
}
'@
$method='public static int Ngs2ParseWaveformDataV1813(CpuContext ctx)'
$idx=$sample.IndexOf($method,[StringComparison]::Ordinal)
if($idx -lt 0) { throw "offline method anchor failed" }
$tail=$sample.Substring($idx)
$rx=[regex]'return\s+SetReturn\(ctx,\s*[^;]+;'
$m=$rx.Matches($tail)
if($m.Count -ne 3) { throw "offline SetReturn match count=$($m.Count)" }
if(-not $m[$m.Count-1].Value.Contains('ORBIS_GEN2_ERROR_INVALID_ARGUMENT')) {
    throw "offline final fallback selection failed"
}

$csv=Import-Csv -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "data\DBFZ_EBOOT_IMPORT_AUDIT.csv")
if($csv.Count -ne 2766) { throw "offline eboot inventory row count=$($csv.Count)" }
Write-Host "[DBFZ-AUDIT-181411] OFFLINE METHOD-BOUND/AUDIT REGRESSION PASSED."
