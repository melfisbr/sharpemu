. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kt=Get-Content -LiteralPath $kernel -Raw
$nt=Get-Content -LiteralPath $ngs -Raw

$kernelMarker='SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14'
$ngsMarker='SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14'

if(-not $kt.Contains('private static string _applicationTitleId = "UNKNOWN";')) { throw "Kernel application title anchor missing." }
if(-not $kt.Contains('public static bool IsReadOnlyGuestMutationPath(string guestPath)')) { throw "Kernel read-only policy method missing." }
if(-not $kt.Contains('var normalized = NormalizeGuestStatCachePath(guestPath);')) { throw "Kernel normalized path anchor missing." }

if(-not $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_WAVEFORM_ABI_PROBE_V1_8_13')) { throw "V1.8.13 NGS2 probe prerequisite missing." }
if(-not $nt.Contains('Nid = "hyVLT2VlOYk"')) { throw "hyVLT2VlOYk export missing." }
if(-not $nt.Contains('return SetReturn(ctx, unchecked((int)0x80020016));') -and -not $nt.Contains($ngsMarker)) {
    throw "NGS2 V1.8.13 return anchor missing."
}

$kernelState=if($kt.Contains($kernelMarker)) { "AlreadyApplied" } else { "ReadyStructural" }
$ngsState=if($nt.Contains($ngsMarker)) { "AlreadyApplied" } else { "ReadyStructural" }

Write-Host "[DBFZ-AUDIT-1814] RepoRoot=$repo"
Write-Host "[DBFZ-AUDIT-1814] Kernel SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $kernel).Hash.ToLowerInvariant()) State=$kernelState"
Write-Host "[DBFZ-AUDIT-1814] Ngs2 SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ngs).Hash.ToLowerInvariant()) State=$ngsState"
Write-Host "[DBFZ-AUDIT-1814] Scope: DBFZ/PPSA09790 only; no Pad/SharePlay ABI fabrication."
Write-Host "[DBFZ-AUDIT-1814] PRECHECK PASSED."
