param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
Assert-V7618GuestOnlyBaseline $repo
foreach($spec in $PatchSpecs){Apply-Patch $repo $spec}
$state=Get-SamplerHelperState $repo
if($state -eq 'ReadyCopy'){
    $target=Join-Path $repo $SamplerRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackageRoot $SamplerPayload) -Destination $target -Force
    Write-Host '  * bink-guest-yuv-integer-sampler-v7624'
}
Assert-V7624Installed $repo
Write-Host "[$PackageTag] APPLY VERIFY PASSED."
