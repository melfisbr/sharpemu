param()
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$backup=Find-PreV75Backup
$rad=Get-InstalledRadVideo64

Write-Tag "PackageRoot=$script:PackageRoot"
Write-Tag "PatchesRoot=$(Get-PatchesRoot)"
Write-Tag "RepositoryRoot=$repo"
Write-Tag "PreV75BackupFound=$($null -ne $backup)"
if($null -ne $backup){
    Write-Tag "PreV75Backup=$($backup.FullName)"
}
Write-Tag "RADVideo64Found=$($null -ne $rad)"
if($null -ne $rad){
    Write-Tag "RADVideo64=$rad"
}
if($null -eq $backup){
    throw "$script:Tag clean pre-V75 backup not found"
}
if($null -eq $rad){
    throw "$script:Tag RAD Video Tools rvideo64.exe not found"
}
Write-Tag 'PATH CHECK PASSED'
