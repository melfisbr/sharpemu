param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-V7612Baseline $RepoRoot

$helperTarget=Join-Path $RepoRoot $AvHelperRel
$currentAvHelperHash=Get-Sha256 $helperTarget
if([string]::IsNullOrWhiteSpace($currentAvHelperHash)){
    New-Item -ItemType Directory -Path (Split-Path -Parent $helperTarget) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackageRoot $AvHelperPayloadRel) -Destination $helperTarget -Force
    Write-Host '  * bink-guest-av-clock-helper-v7613'
}elseif($currentAvHelperHash -eq $AvHelperExpectedHashV7613){
    Write-Host '  = bink-guest-av-clock-helper-v7613 already'
}else{
    throw "V76.0.13 A/V helper divergente actual=$currentAvHelperHash"
}

Apply-BinkPatchV7613 $RepoRoot
Apply-PresenterPatchV7613 $RepoRoot
Assert-V7613Installed $RepoRoot
