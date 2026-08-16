. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$nt=Get-Content -LiteralPath $ngs -Raw
$kt=Get-Content -LiteralPath $kernel -Raw
$checks=[ordered]@{
 riff_atrac9_preserve=$nt.Contains('SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15')
 old_zero_fill_removed=(-not $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2'))
 zero_fill_code_removed=(-not $nt.Contains('compatibilityOutput = stackalloc byte[0x240]'))
 atrac9_guid_check=$nt.Contains('riff[44] == 0xD2')
 default_fallback_preserved=$nt.Contains('return SetReturn(ctx,')
 full_app0_dbfz=$kt.Contains('SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15')
 retail_policy_preserved=$kt.Contains('NormalizeGuestStatCachePath(guestPath)')
}
foreach($kv in $checks.GetEnumerator()){
 Write-Host "[DBFZ-RIFF-1815] $($kv.Key)=$($kv.Value)"
 if(-not $kv.Value){throw "Post-audit failed: $($kv.Key)"}
}
Write-Host "[DBFZ-RIFF-1815] POST-AUDIT PASSED."
