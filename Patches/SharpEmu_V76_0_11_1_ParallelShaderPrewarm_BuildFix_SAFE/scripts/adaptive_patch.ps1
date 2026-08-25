param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-V76102Baseline $RepoRoot

$cacheTarget=Join-Path $RepoRoot $CacheRel
$cacheHash=Get-Sha256 $cacheTarget
if($cacheHash -eq $CacheV76102Hash){
    Copy-Item -LiteralPath (Join-Path $PackageRoot $CachePayloadRel) -Destination $cacheTarget -Force
    Write-Host '  * spirv-background-prewarm-v7611'
}elseif($cacheHash -eq $CacheV7611Hash){
    Write-Host '  = spirv-background-prewarm-v7611 already'
}else{ throw "Cache helper divergente antes do apply: $cacheHash" }

$helperTarget=Join-Path $RepoRoot $AgcParallelRel
$helperHash=Get-Sha256 $helperTarget
if($helperHash -eq '' -or $helperHash -eq $AgcParallelBuggyHash){
    Copy-Item -LiteralPath (Join-Path $PackageRoot $AgcParallelPayloadRel) -Destination $helperTarget -Force
    if($helperHash -eq $AgcParallelBuggyHash){
        Write-Host '  * parallel-stage-helper-v7611-definite-assignment-buildfix'
    }else{
        Write-Host '  * parallel-stage-helper-v7611-buildfix'
    }
}elseif($helperHash -eq $AgcParallelHash){
    Write-Host '  = parallel-stage-helper-v7611-buildfix already'
}else{ throw "AGC parallel helper divergente antes do apply: $helperHash" }

Apply-AgcParallelPatchV7611 $RepoRoot
Assert-V7611Installed $RepoRoot
