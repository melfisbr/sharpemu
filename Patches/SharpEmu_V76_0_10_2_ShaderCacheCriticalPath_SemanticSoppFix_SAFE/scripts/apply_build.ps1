param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
Assert-V76093Baseline $repo
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir=Join-Path $patches "_SharpEmu_V76_0_10_2_PREVIOUS_FILES_$stamp"
$backupZip=Join-Path $patches "SharpEmu_V76_0_10_2_PREVIOUS_FILES_$stamp.zip"
$buildLog=Join-Path $patches "SharpEmu_V76_0_10_2_BUILD_$stamp.log"
$summary=Join-Path $patches "SharpEmu_V76_0_10_2_SUMMARY_$stamp.txt"
$resultZip=Join-Path $patches "SharpEmu_V76_0_10_2_RESULT_$stamp.zip"
$didMutate=$false; $rollbackCompleted=$false
function Restore-Backup {
    foreach($rel in $AffectedExistingFiles) {
        $source=Join-Path $backupDir $rel; $target=Join-Path $repo $rel
        if(Test-Path -LiteralPath $source -PathType Leaf){ Copy-Item -LiteralPath $source -Destination $target -Force }
    }
}
try {
    foreach($rel in $AffectedExistingFiles) {
        $source=Join-Path $repo $rel
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){ throw "Arquivo alvo ausente: $rel" }
        $backup=Join-Path $backupDir $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $backup -Force
    }
    Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] Backup=$backupZip"
    $didMutate=$true
    & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    Assert-V7610Installed $repo
    Write-Host "[$PackageTag] APPLY VERIFY PASSED."
    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building $project (Release / win-x64)..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $exit=$LASTEXITCODE
    if($exit -ne 0) {
        Restore-Backup; $rollbackCompleted=$true
        @("Tag=$PackageTag",'Status=BUILD_FAILED_ROLLBACK',"ExitCode=$exit","Backup=$backupZip","BuildLog=$buildLog") | Set-Content -LiteralPath $summary -Encoding UTF8
        if(Test-Path -LiteralPath $resultZip){Remove-Item -LiteralPath $resultZip -Force}
        Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
        throw "BUILD FAILED; rollback concluido. Resultado: $resultZip"
    }
    Assert-V7610Installed $repo
    @("Tag=$PackageTag",'Status=BUILD_PASSED',"RepositoryRoot=$repo","Backup=$backupZip","BuildLog=$buildLog",'SpirvCacheVersion=V76.0.10-r1','DiskWrites=single background queue','CacheEnvironment=semantic compiler switches only','SClause=host scheduling no-op','SWaitcntDepctr=scoreboard dependency no-op') | Set-Content -LiteralPath $summary -Encoding UTF8
    if(Test-Path -LiteralPath $resultZip){Remove-Item -LiteralPath $resultZip -Force}
    Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] BUILD PASSED."
    Write-Host "[$PackageTag] Summary=$summary"
    Write-Host "[$PackageTag] Result=$resultZip"
} catch {
    if($didMutate -and -not $rollbackCompleted) {
        try { Restore-Backup; $rollbackCompleted=$true; Write-Host "[$PackageTag] Emergency rollback COMPLETED." -ForegroundColor Yellow }
        catch { Write-Warning "Rollback secundario falhou: $($_.Exception.Message)" }
    }
    throw
} finally {
    if(Test-Path -LiteralPath $backupDir -PathType Container){Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue}
}
