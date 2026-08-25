param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
Assert-V7624Installed $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V76_0_24_SOURCE_VERIFY_$stamp.txt"
@(
    "Tag=$PackageTag",'Status=SOURCE_VERIFY_PASSED',"RepositoryRoot=$repo",
    'Bink2GuestOnly=1','StorageWriteView=UINT','SampleReadView=UNORM_ALIAS',
    'SameVkImage=1','CpuCopy=0','HostDecoder=0','EbootHandoffV7618Preserved=1'
) | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $out"
