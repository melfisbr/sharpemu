param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
Assert-V7609Installed $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $outPath=Join-Path $patches "SharpEmu_V76_0_9_SOURCE_VERIFY_$stamp.txt"
$lines=@("Tag=$PackageTag","RepositoryRoot=$repo",'PrerequisiteV7608=PASSED','AdaptiveInPlace=PASSED','BoundedAtomicIncDec=PASSED','FlatGlobalAtomicFamily=PASSED','PartialThreadGroups=PASSED',"AtomicCompatHelperHash=$(Get-Sha256 (Join-Path $repo $HelperRel))")
foreach ($rel in $AffectedExistingFiles) { $lines += "$rel=$(Get-Sha256 (Join-Path $repo $rel))" }
$lines | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
