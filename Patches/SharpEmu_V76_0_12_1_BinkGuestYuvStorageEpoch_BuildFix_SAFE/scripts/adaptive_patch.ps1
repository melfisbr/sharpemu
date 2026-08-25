param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-V7611Baseline $RepoRoot

$helperTarget=Join-Path $RepoRoot $HelperRel
$currentHelperHash=Get-Sha256 $helperTarget
if($currentHelperHash -eq ''){
    New-Item -ItemType Directory -Path (Split-Path -Parent $helperTarget) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackageRoot $HelperPayloadRel) -Destination $helperTarget -Force
    Write-Host '  * bink-yuv-epoch-helper-v7612'
}elseif($currentHelperHash -eq $HelperExpectedHashV7612){
    Write-Host '  = bink-yuv-epoch-helper-v7612 already'
}else{
    throw "Bink YUV V76.0.12.1 helper divergente actual=$currentHelperHash"
}

Apply-BinkPatchV7612 $RepoRoot
Apply-PresenterPatchV7612 $RepoRoot
Assert-V7612Installed $RepoRoot
