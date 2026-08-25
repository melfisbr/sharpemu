param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
Assert-V7624Baseline $repo

$helperTarget=Join-Path $repo $HelperRel
$helperSource=Join-Path $PackageRoot $HelperPayload
if(Test-Path -LiteralPath $helperTarget -PathType Leaf){
    $existing=Get-Sha256 $helperTarget
    $payload=Get-Sha256 $helperSource
    if($existing -ne $payload){throw "Helper V76.0.24 divergente: $HelperRel existing=$existing payload=$payload"}
}else{
    New-Item -ItemType Directory -Path (Split-Path -Parent $helperTarget) -Force | Out-Null
    Copy-Item -LiteralPath $helperSource -Destination $helperTarget -Force
    Write-Host "  * bink-yuv-normalized-sample-view-helper-v7624"
}
foreach($spec in $PatchSpecs){ Apply-Patch $repo $spec }
Assert-V7624Installed $repo
