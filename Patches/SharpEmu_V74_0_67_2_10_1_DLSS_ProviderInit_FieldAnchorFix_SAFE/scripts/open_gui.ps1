. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot;$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}
Write-Host '[V74.0.67.2.10.1] Opening accumulated SharpEmu Release host.'
Write-Host '[V74.0.67.2.10.1] Rendering -> DLSS.'
Write-Host '[V74.0.67.2.10.1] V2.9 scene gate is already expected selected.'
Write-Host '[V74.0.67.2.10.1] Watch PROVIDER_LOAD and PROVIDER_INIT for exact NGX result/last_error.'
Write-Host '[V74.0.67.2.10.1] Full proof: selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.10.1] Host=$($releaseHost.FullName)"
Start-Process -FilePath $releaseHost.FullName -WorkingDirectory $releaseHost.DirectoryName
