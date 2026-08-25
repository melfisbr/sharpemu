param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot; $state=Get-V7609State $repo
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir=Join-Path $patches "_SharpEmu_V76_0_9_1_PREVIOUS_FILES_$stamp"
$backupZip=Join-Path $patches "SharpEmu_V76_0_9_1_PREVIOUS_FILES_$stamp.zip"
$buildLog=Join-Path $patches "SharpEmu_V76_0_9_1_BUILD_$stamp.log"
$summary=Join-Path $patches "SharpEmu_V76_0_9_1_SUMMARY_$stamp.txt"
$resultZip=Join-Path $patches "SharpEmu_V76_0_9_1_RESULT_$stamp.zip"
$didMutate=$false; $rollbackCompleted=$false
$helperExistedBefore=Test-Path -LiteralPath (Join-Path $repo $HelperRel) -PathType Leaf
function Restore-Backup {
    foreach ($rel in $AffectedExistingFiles) {
        $source=Join-Path $backupDir $rel; $destination=Join-Path $repo $rel
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $destination -Force }
    }
    $helperBackup=Join-Path $backupDir $HelperRel; $helperTarget=Join-Path $repo $HelperRel
    if ($helperExistedBefore) { if (Test-Path -LiteralPath $helperBackup -PathType Leaf) { Copy-Item -LiteralPath $helperBackup -Destination $helperTarget -Force } }
    elseif (Test-Path -LiteralPath $helperTarget -PathType Leaf) { Remove-Item -LiteralPath $helperTarget -Force }
}
try {
    if ($state -ne 'AlreadyApplied') {
        foreach ($rel in $AffectedExistingFiles) {
            $source=Join-Path $repo $rel; $backupPath=Join-Path $backupDir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $backupPath -Force
        }
        if ($helperExistedBefore) {
            $source=Join-Path $repo $HelperRel; $backupPath=Join-Path $backupDir $HelperRel
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $backupPath -Force
        }
        Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
        Write-Host "[$PackageTag] Backup=$backupZip"
        $didMutate=$true
        & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    } else { Write-Host "[$PackageTag] V76.0.9.1 ja aplicada; executando verify + build." }
    Assert-V7609Installed $repo
    Write-Host "[$PackageTag] APPLY VERIFY PASSED."
    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building $project (Release / win-x64)..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit=$LASTEXITCODE
    if ($buildExit -ne 0) {
        if ($didMutate) { Restore-Backup; $rollbackCompleted=$true }
        @("Tag=$PackageTag",'Status=BUILD_FAILED_ROLLBACK',"ExitCode=$buildExit","Backup=$backupZip","BuildLog=$buildLog",'ApplyMode=adaptive-in-place-with-v7608-prerequisite-repair') | Set-Content -LiteralPath $summary -Encoding UTF8
        if (Test-Path -LiteralPath $resultZip) { Remove-Item -LiteralPath $resultZip -Force }
        Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
        throw "BUILD FAILED; rollback concluido. Resultado: $resultZip"
    }
    Assert-V7609Installed $repo
    @("Tag=$PackageTag",'Status=BUILD_PASSED',"RepositoryRoot=$repo","InitialState=$state","Backup=$backupZip","BuildLog=$buildLog",'ApplyMode=adaptive-in-place-with-v7608-prerequisite-repair','AtomicIncDec=bounded CAS with DATA clamp for LDS/buffer/global/image','FlatGlobalAtomics=32-bit family 0x30..0x3D supported','PartialThreadGroups=exact thread limits through existing compute push-constant guard') | Set-Content -LiteralPath $summary -Encoding UTF8
    if (Test-Path -LiteralPath $resultZip) { Remove-Item -LiteralPath $resultZip -Force }
    Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] BUILD PASSED."; Write-Host "[$PackageTag] Summary=$summary"; Write-Host "[$PackageTag] Result=$resultZip"
} catch {
    if ($didMutate -and -not $rollbackCompleted) {
        try { Restore-Backup; $rollbackCompleted=$true; Write-Host "[$PackageTag] Emergency rollback COMPLETED." -ForegroundColor Yellow }
        catch { Write-Warning "Rollback secundario falhou: $($_.Exception.Message)" }
    }
    throw
} finally {
    if (Test-Path -LiteralPath $backupDir -PathType Container) { Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue }
}
