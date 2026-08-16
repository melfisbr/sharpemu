. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kt=Get-Content -LiteralPath $kernel -Raw
$nt=Get-Content -LiteralPath $ngs -Raw

if(-not $kt.Contains('private static string _applicationTitleId = "UNKNOWN";') -and
   -not $kt.Contains('CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId)')) {
    throw "Kernel application title anchor missing."
}
if(-not $kt.Contains('public static bool IsReadOnlyGuestMutationPath(string guestPath)')) {
    throw "Kernel read-only policy method missing."
}

if(-not $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_WAVEFORM_ABI_PROBE_V1_8_13')) {
    throw "V1.8.13 ParseWaveform marker missing."
}
if(-not $nt.Contains('Nid = "hyVLT2VlOYk"')) {
    throw "hyVLT2VlOYk export missing."
}
if(-not $nt.Contains('Ngs2ParseWaveformDataV1813')) {
    throw "Ngs2ParseWaveformDataV1813 method missing."
}

$kernelState = if($kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_1') -or
                  $kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14')) {
    "AlreadyApplied"
} else {
    "ReadyStructural"
}

if($nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_1') -or $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14')) {
    $ngsState="AlreadyApplied"
} elseif($nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_WAVEFORM_COMPAT_AB_V1_8_13_3')) {
    $ngsState="ReadyFromV18133"
} else {
    $ngsState="ReadyMethodBound"
}

Write-Host "[DBFZ-AUDIT-181411] RepoRoot=$repo"
Write-Host "[DBFZ-AUDIT-181411] Kernel SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $kernel).Hash.ToLowerInvariant()) State=$kernelState"
Write-Host "[DBFZ-AUDIT-181411] Ngs2 SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ngs).Hash.ToLowerInvariant()) State=$ngsState"
Write-Host "[DBFZ-AUDIT-181411] NGS2 patching is method-bound; exact INVALID_ARGUMENT text is not required."
Write-Host "[DBFZ-AUDIT-181411] Scope: PPSA09790 only; unknown Pad/SharePlay ABIs remain untouched."
Write-Host "[DBFZ-AUDIT-181411] PRECHECK PASSED."
