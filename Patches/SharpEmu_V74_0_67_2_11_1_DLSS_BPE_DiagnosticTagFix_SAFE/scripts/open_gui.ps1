. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

Write-Host '[V74.0.67.2.11.1] Opening accumulated SharpEmu Release host.'
Write-Host '[V74.0.67.2.11.1] Use Rendering -> DLSS.'
Write-Host '[V74.0.67.2.11.1] Source/depth/motion are already resolved by V2.9/V2.5/V2.6.'
Write-Host '[V74.0.67.2.11.1] Watch PROVIDER_INIT for state=active or exact last_error.'
Write-Host '[V74.0.67.2.11.1] Crash proof: BPE recovery must return rax=payload and AV target 0x20 must disappear.'
Write-Host '[V74.0.67.2.11.1] DLSS proof: selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.11.1] Host=$($releaseHost.FullName)"

Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName
