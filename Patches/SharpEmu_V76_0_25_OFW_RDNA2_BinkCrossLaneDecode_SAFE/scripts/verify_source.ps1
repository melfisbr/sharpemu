param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_25_SOURCE_VERIFY_$stamp.txt"
Assert-V7625Installed $repo
@(
  "Tag=$PackageTag",'Status=SOURCE_VERIFY_PASSED',"RepositoryRoot=$repo",
  'DS_PERMUTE_B32=implemented','DS_BPERMUTE_B32=implemented',
  'DPP_reserved_identity_fallback=removed','Bink_UNORM_sample_alias=disabled',
  'HybridHostDecoder=disabled','HostDecoder=0'
) | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
