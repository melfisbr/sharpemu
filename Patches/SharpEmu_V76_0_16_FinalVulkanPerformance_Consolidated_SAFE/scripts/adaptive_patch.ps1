param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
Assert-V7613Baseline $repo
foreach($spec in $HelperSpecs){
    $state=Get-HelperState $repo $spec
    if($state -eq 'ReadyCopy'){
        $target=Join-Path $repo $spec.Rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PackageRoot $spec.Payload) -Destination $target -Force
        Write-Host "  * helper $($spec.Rel)"
    }
}
for($i=1;$i -le 15;$i++){Apply-PatchPair $repo $PresenterRel 'presenter' $i}
for($i=1;$i -le 14;$i++){Apply-PatchPair $repo $DetileRel 'detile' $i}
Assert-FinalInstalled $repo
