param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
Assert-V7625Baseline $repo

$helperTarget=Join-Path $repo $HelperRel
$helperSource=Join-Path $PackageRoot $HelperPayload
if(Test-Path -LiteralPath $helperTarget -PathType Leaf){
    if((Get-Sha256 $helperTarget) -ne (Get-Sha256 $helperSource)){
        throw "Helper V76.0.25 divergente: $HelperRel"
    }
}else{
    New-Item -ItemType Directory -Path (Split-Path -Parent $helperTarget) -Force | Out-Null
    Copy-Item -LiteralPath $helperSource -Destination $helperTarget -Force
    Write-Host '  * rdna2-ds-permute-bpermute-v7625'
}
foreach($spec in $PatchSpecs){Apply-Patch $repo $spec}
Assert-V7625Installed $repo
