. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

Write-Host '[V74.0.67.2.10.2] Opening accumulated SharpEmu Release host.'
Write-Host '[V74.0.67.2.10.2] Use Rendering -> DLSS.'
Write-Host '[V74.0.67.2.10.2] Source/depth/motion are already resolved by V2.9/V2.5/V2.6.'
Write-Host '[V74.0.67.2.10.2] Watch PROVIDER_INIT for state=active or exact last_error.'
Write-Host '[V74.0.67.2.10.2] Full proof: selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.10.2] Host=$($releaseHost.FullName)"

Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName
