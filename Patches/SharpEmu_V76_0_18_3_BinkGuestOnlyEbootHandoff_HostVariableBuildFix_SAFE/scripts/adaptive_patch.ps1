param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
Assert-V7616Baseline $repo
foreach($spec in $PatchSpecs){Apply-Patch $repo $spec}
$target=Join-Path $repo $HandoffRel
$payload=Join-Path $PackageRoot $HandoffPayload
$state=Get-HandoffHelperState $repo
if($state -eq 'ReadyCopy'){
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $payload -Destination $target -Force
    Write-Host '  * bink-guest-eboot-handoff-helper-v7618'
}
Assert-V7618Installed $repo
