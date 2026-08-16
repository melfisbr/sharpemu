. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$nt=Get-Content -LiteralPath $ngs -Raw
$kt=Get-Content -LiteralPath $kernel -Raw

foreach($r in @(
 'Ngs2ParseWaveformDataV1813',
 'SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2',
 'stackalloc byte[0x240]',
 'CurrentApplicationTitleId',
 'IsReadOnlyGuestMutationPath'
)){
 if(-not($nt.Contains($r) -or $kt.Contains($r))){throw "Required cumulative anchor missing: $r"}
}
Write-Host "[DBFZ-RIFF-1815] RepoRoot=$repo"
Write-Host "[DBFZ-RIFF-1815] Ngs2 SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ngs).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-RIFF-1815] Kernel SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $kernel).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-RIFF-1815] destructive_zero_fill_present=$($nt.Contains('stackalloc byte[0x240]'))"
Write-Host "[DBFZ-RIFF-1815] PRECHECK PASSED."
