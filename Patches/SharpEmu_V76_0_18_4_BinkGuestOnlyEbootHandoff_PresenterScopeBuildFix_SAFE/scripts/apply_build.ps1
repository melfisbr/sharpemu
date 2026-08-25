param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
Assert-V7616Baseline $repo
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir=Join-Path $patches "_SharpEmu_V76_0_18_4_PREVIOUS_FILES_$stamp"
$backupZip=Join-Path $patches "SharpEmu_V76_0_18_4_PREVIOUS_FILES_$stamp.zip"
$debugLog=Join-Path $patches "SharpEmu_V76_0_18_4_DEBUG_BUILD_$stamp.log"
$releaseLog=Join-Path $patches "SharpEmu_V76_0_18_4_RELEASE_BUILD_$stamp.log"
$rollbackDebugLog=Join-Path $patches "SharpEmu_V76_0_18_4_ROLLBACK_DEBUG_BUILD_$stamp.log"
$rollbackReleaseLog=Join-Path $patches "SharpEmu_V76_0_18_4_ROLLBACK_RELEASE_BUILD_$stamp.log"
$summary=Join-Path $patches "SharpEmu_V76_0_18_4_SUMMARY_$stamp.txt"
$resultZip=Join-Path $patches "SharpEmu_V76_0_18_4_RESULT_$stamp.zip"
$targets=@($BinkRel,$KernelRel,$HostRel,$FfmpegRel,$NihavRel,$RadNativeRel,$RadExternalRel,$PresenterRel,$HandoffRel) | Select-Object -Unique
$existed=@{}
$didMutate=$false
$rollbackCompleted=$false
$buildStarted=$false
function Restore-Backup {
    foreach($rel in $targets){
        $target=Join-Path $repo $rel
        if($existed[$rel]){
            $source=Join-Path $backupDir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        }elseif(Test-Path -LiteralPath $target -PathType Leaf){
            Remove-Item -LiteralPath $target -Force
        }
    }
}
function Rebuild-RollbackBinaries {
    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    try{& dotnet build $project -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $rollbackDebugLog | Out-Host}catch{}
    try{& dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $rollbackReleaseLog | Out-Host}catch{}
}
try{
    foreach($rel in $targets){
        $source=Join-Path $repo $rel
        $exists=Test-Path -LiteralPath $source -PathType Leaf
        $existed[$rel]=$exists
        if($exists){
            $backup=Join-Path $backupDir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $backup -Force
        }
    }
    if(Test-Path -LiteralPath $backupDir -PathType Container){Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force}
    Write-Host "[$PackageTag] Backup=$backupZip"
    $didMutate=$true
    & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    Assert-V7618Installed $repo
    Write-Host "[$PackageTag] APPLY VERIFY PASSED."

    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    $buildStarted=$true
    Write-Host "[$PackageTag] Building DEBUG / win-x64 (this is the executable used by manual Debug tests)..."
    & dotnet build $project -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $debugLog
    $debugExit=$LASTEXITCODE
    if($debugExit -ne 0){throw "DEBUG BUILD FAILED exit=$debugExit"}

    Write-Host "[$PackageTag] Building RELEASE / win-x64..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $releaseLog
    $releaseExit=$LASTEXITCODE
    if($releaseExit -ne 0){throw "RELEASE BUILD FAILED exit=$releaseExit"}

    Assert-V7618Installed $repo
    @(
      "Tag=$PackageTag",'Status=BUILD_PASSED',"RepositoryRoot=$repo","Backup=$backupZip","DebugBuildLog=$debugLog","ReleaseBuildLog=$releaseLog",
      'Bink2Owner=guest-hard-enforced','FfmpegBink2=blocked','NihavBink2=blocked','RadHostBink2=blocked',
      'KernelBinkOpen=normal-guest-file-fd','CompletionShim=disabled-for-bk2','EbootHandoff=guest-close-no-black-no-host-wait',
      'DebugAndReleaseBuilt=1','V76.0.16Performance=preserved'
    ) | Set-Content -LiteralPath $summary -Encoding UTF8
    if(Test-Path -LiteralPath $resultZip){Remove-Item -LiteralPath $resultZip -Force}
    Compress-Archive -LiteralPath $summary,$debugLog,$releaseLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] BUILD PASSED (Debug + Release)."
    Write-Host "[$PackageTag] Summary=$summary"
    Write-Host "[$PackageTag] Result=$resultZip"
}catch{
    $message=$_.Exception.Message
    if($didMutate -and -not $rollbackCompleted){
        try{
            Restore-Backup
            $rollbackCompleted=$true
            Write-Host "[$PackageTag] Emergency rollback COMPLETED." -ForegroundColor Yellow
            if($buildStarted){Rebuild-RollbackBinaries}
        }catch{Write-Warning "Rollback secundario falhou: $($_.Exception.Message)"}
    }
    @("Tag=$PackageTag",'Status=FAILED_ROLLBACK',"Error=$message","Backup=$backupZip","DebugBuildLog=$debugLog","ReleaseBuildLog=$releaseLog") | Set-Content -LiteralPath $summary -Encoding UTF8
    $toZip=@($summary)
    foreach($p in @($debugLog,$releaseLog,$rollbackDebugLog,$rollbackReleaseLog)){if(Test-Path -LiteralPath $p -PathType Leaf){$toZip += $p}}
    if(Test-Path -LiteralPath $resultZip){Remove-Item -LiteralPath $resultZip -Force}
    Compress-Archive -LiteralPath $toZip -DestinationPath $resultZip -CompressionLevel Optimal -Force
    throw "$message Resultado: $resultZip"
}finally{
    if(Test-Path -LiteralPath $backupDir -PathType Container){Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue}
}
