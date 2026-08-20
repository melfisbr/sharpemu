. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

Write-Host '[V74.0.67.2.12] Opening accumulated SharpEmu Release host.'
Write-Host '[V74.0.67.2.12] Use Rendering -> DLSS.'
Write-Host '[V74.0.67.2.12] Expected BPE secondary telemetry: variant=secondary-r13-r15 last_import=GuchCTefuZw.'
Write-Host '[V74.0.67.2.12] Both BPE variants must return rax=payload.'
Write-Host '[V74.0.67.2.12] DLSS telemetry owner remains V74.0.67.2.10.2.'
Write-Host '[V74.0.67.2.12] DLSS proof: selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.12] Host=$($releaseHost.FullName)"
Start-Process -FilePath $releaseHost.FullName -WorkingDirectory $releaseHost.DirectoryName
