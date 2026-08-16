. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kt=Get-Content -LiteralPath $kernel -Raw
$nt=Get-Content -LiteralPath $ngs -Raw

$openEvidence=Find-SourceEvidence $repo @(
  'Nid = "1G3lF1Gg1k8"',
  'ExportName = "sceKernelOpen"',
  'KernelOpen(CpuContext'
)
$mkdirEvidence=Find-SourceEvidence $repo @(
  'Nid = "1-LFLmRFxxM"',
  'ExportName = "sceKernelMkdir"',
  'KernelMkdir(CpuContext'
)
$aprEvidence=Find-SourceEvidence $repo @(
  'Nid = "gEpBkcwxUjw"',
  'ExportName = "sceKernelAprResolveFilepathsToIdsAndFileSizes"'
)

$kernelAuto=$kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_2')
$ngsAuto=$nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2')

$checks=[ordered]@{
  kernel_title_bridge=$kt.Contains('CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId)')
  kernel_dbfz_saved=$kernelAuto
  kernel_saved_scope=$kt.Contains('"/app0/red/saved/"')
  ngs_dbfz_parse=$ngsAuto
  ngs_record_size=$nt.Contains('stackalloc byte[0x240]')
  ngs_title_scope=$nt.Contains('"PPSA09790"')
  ngs_method_preserved=$nt.Contains('Ngs2ParseWaveformDataV1813')
  apr_preserved=($aprEvidence.Count -gt 0)
  mkdir_preserved=($mkdirEvidence.Count -gt 0)
  open_preserved=($openEvidence.Count -gt 0)
}

foreach($kv in $checks.GetEnumerator()) {
  Write-Host "[DBFZ-AUDIT-181421] $($kv.Key)=$($kv.Value)"
  if(-not $kv.Value) {throw "Post-audit failed: $($kv.Key)"}
}

Write-Host "[DBFZ-AUDIT-181421] sceKernelOpen evidence: $([string]::Join('; ', $openEvidence))"
Write-Host "[DBFZ-AUDIT-181421] sceKernelMkdir evidence: $([string]::Join('; ', $mkdirEvidence))"
Write-Host "[DBFZ-AUDIT-181421] APR evidence: $([string]::Join('; ', $aprEvidence))"
Write-Host "[DBFZ-AUDIT-181421] POST-AUDIT PASSED."
