. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$nt=Get-Content -LiteralPath $ngs -Raw
$kt=Get-Content -LiteralPath $kernel -Raw

$newNgs=$nt.Contains('SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15_1')
$oldNgs=$nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2')
$newKernel=$kt.Contains('SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15_1')

if(-not $nt.Contains('Ngs2ParseWaveformDataV1813')){throw "Ngs2ParseWaveformDataV1813 missing."}
if(-not $nt.Contains('CurrentApplicationTitleId')){
    if(-not $kt.Contains('CurrentApplicationTitleId')){throw "CurrentApplicationTitleId bridge missing."}
}
if(-not $kt.Contains('IsReadOnlyGuestMutationPath')){throw "Kernel read-only policy method missing."}

if($newNgs -and $newKernel){
    $state="AlreadyApplied"
} elseif($oldNgs){
    $state="NeedsV1_8_15_1Apply"
} else {
    throw "Neither old V1.8.14.2 NGS2 block nor applied V1.8.15.1 RIFF block found."
}

Write-Host "[DBFZ-RIFF-18152] RepoRoot=$repo"
Write-Host "[DBFZ-RIFF-18152] Ngs2 SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ngs).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-RIFF-18152] Kernel SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $kernel).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-RIFF-18152] State=$state"
Write-Host "[DBFZ-RIFF-18152] new_riff_marker=$newNgs old_zero_fill_marker=$oldNgs app0_marker=$newKernel"
Write-Host "[DBFZ-RIFF-18152] PRECHECK PASSED."
