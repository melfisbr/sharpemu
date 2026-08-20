. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot
$releaseHost = Find-ReleaseHost -Repo $repo

if ($null -eq $releaseHost) {
    throw 'SharpEmu.exe not found.'
}

Write-Host '[V74.0.67.2.9] Opening accumulated SharpEmu Release host.'
Write-Host '[V74.0.67.2.9] Use Rendering -> DLSS.'
Write-Host '[V74.0.67.2.9] Expected: SOURCE_RESOLVE raw_candidates=5 distinct_sources=1 state=selected.'
Write-Host '[V74.0.67.2.9] Then watch for NGX init/create/evaluate.'
Write-Host '[V74.0.67.2.9] Full proof: selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.9] Host=$($releaseHost.FullName)"

Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName
