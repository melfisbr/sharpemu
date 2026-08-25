param(
    [string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $patches "SharpEmu_V76_2_4_PREVIOUS_FILES_$stamp.zip"
$debugLog=Join-Path $patches "SharpEmu_V76_2_4_DEBUG_BUILD_$stamp.log"
$releaseLog=Join-Path $patches "SharpEmu_V76_2_4_RELEASE_BUILD_$stamp.log"
$rollbackDebugLog=Join-Path $patches "SharpEmu_V76_2_4_ROLLBACK_DEBUG_BUILD_$stamp.log"
$rollbackReleaseLog=Join-Path $patches "SharpEmu_V76_2_4_ROLLBACK_RELEASE_BUILD_$stamp.log"
$summary=Join-Path $patches "SharpEmu_V76_2_4_SUMMARY_$stamp.txt"
$resultZip=Join-Path $patches "SharpEmu_V76_2_4_RESULT_$stamp.zip"
$temp=Join-Path $patches "_V76_2_4_BACKUP_$stamp"
$resultDir=Join-Path $patches "_V76_2_4_RESULT_$stamp"
$rels=@($PresenterRel,$SamplerRel)
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$existed=@{}
foreach($rel in $rels){
    $src=Join-Path $repo $rel
    $existed[$rel]=Test-Path -LiteralPath $src -PathType Leaf
    if($existed[$rel]){
        $dst=Join-Path $temp $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}
Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $backup -Force
Write-Host "[$PackageTag] Backup=$backup"
function Restore-V7624 {
    foreach($rel in $rels){
        $dst=Join-Path $repo $rel
        $src=Join-Path $temp $rel
        if($existed[$rel]){
            New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Force
        } elseif(Test-Path -LiteralPath $dst) {
            Remove-Item -LiteralPath $dst -Force
        }
    }
    Write-Host "[$PackageTag] Emergency rollback COMPLETED."
}
function Rebuild-RollbackBinariesV7624 {
    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    try{& dotnet build $project -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $rollbackDebugLog | Out-Host}catch{}
    try{& dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $rollbackReleaseLog | Out-Host}catch{}
}
try {
    & (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $PackageRoot
    & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building DEBUG / win-x64..."
    & dotnet build $project -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $debugLog
    $debugExit=$LASTEXITCODE
    if($debugExit -ne 0){throw "DEBUG BUILD FAILED exit=$debugExit"}
    Write-Host "[$PackageTag] Building RELEASE / win-x64..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $releaseLog
    $releaseExit=$LASTEXITCODE
    if($releaseExit -ne 0){throw "RELEASE BUILD FAILED exit=$releaseExit"}
    Assert-V7624Installed $repo
    @(
        "Package=$PackageTag",
        "Timestamp=$stamp",
        "Backup=$backup",
        "DebugBuildLog=$debugLog",
        "ReleaseBuildLog=$releaseLog",
        'DebugBuild=PASSED',
        'ReleaseBuild=PASSED',
        'GuestBinkDecoder=guest-only',
        'YuvStorageFormat=preserved-integer',
        'FinalYuvSampler=nearest/no-mip'
    ) | Set-Content -LiteralPath $summary -Encoding UTF8
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
    Copy-Item -LiteralPath $summary -Destination $resultDir -Force
    Copy-Item -LiteralPath $debugLog -Destination $resultDir -Force
    Copy-Item -LiteralPath $releaseLog -Destination $resultDir -Force
    Copy-Item -LiteralPath (Join-Path $repo $SamplerRel) -Destination $resultDir -Force
    Compress-Archive -Path (Join-Path $resultDir '*') -DestinationPath $resultZip -Force
    Write-Host "[$PackageTag] BUILD PASSED."
    Write-Host "[$PackageTag] Summary=$summary"
    Write-Host "[$PackageTag] Result=$resultZip"
} catch {
    $message=$_.Exception.Message
    Restore-V7624
    Rebuild-RollbackBinariesV7624
    @("Package=$PackageTag","Timestamp=$stamp","Error=$message","Rollback=COMPLETED","Backup=$backup","DebugBuildLog=$debugLog","ReleaseBuildLog=$releaseLog") | Set-Content -LiteralPath $summary -Encoding UTF8
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
    Copy-Item -LiteralPath $summary -Destination $resultDir -Force
    foreach($logPath in @($debugLog,$releaseLog,$rollbackDebugLog,$rollbackReleaseLog)){if(Test-Path -LiteralPath $logPath){Copy-Item -LiteralPath $logPath -Destination $resultDir -Force}}
    Compress-Archive -Path (Join-Path $resultDir '*') -DestinationPath $resultZip -Force
    throw "$message Resultado: $resultZip"
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resultDir -Recurse -Force -ErrorAction SilentlyContinue
}
