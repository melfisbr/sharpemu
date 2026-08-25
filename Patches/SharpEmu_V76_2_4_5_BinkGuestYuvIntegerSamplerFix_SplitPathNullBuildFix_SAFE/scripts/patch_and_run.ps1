. (Join-Path $PSScriptRoot 'common.ps1')

& (Join-Path $PSScriptRoot 'validate.ps1')

$state = Get-TargetStateV76245
if ($state -eq 'MissingTarget' -or $state -eq 'MissingScript' -or $state -eq 'MissingRunner') {
    throw "$PackageTag target package incomplete: state=$state"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $PatchesRoot ("SharpEmu_V76_2_4_5_TARGET_SCRIPT_BACKUP_{0}" -f $stamp)
$resultLog = Join-Path $PatchesRoot ("SharpEmu_V76_2_4_5_RUNNER_{0}.log" -f $stamp)
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$scriptBackup = Join-Path $backupDir 'patch_target.ps1'
Copy-Item -LiteralPath $TargetScript -Destination $scriptBackup -Force
$manifestBackup = $null
if (Test-Path -LiteralPath $TargetManifest -PathType Leaf) {
    $manifestBackup = Join-Path $backupDir 'manifest.sha256'
    Copy-Item -LiteralPath $TargetManifest -Destination $manifestBackup -Force
}

try {
    $repairState = Repair-TargetScriptV76245
    $manifestUpdated = Update-TargetManifestV76245
    Write-Host "$PackageTag patch_target.ps1 repair=$repairState manifest_updated=$manifestUpdated"

    Assert-PowerShellParsesV76245 $TargetScript
    $postText = Read-TextV76245 $TargetScript
    $remaining = Get-SuspiciousSplitPathCountV76245 $postText
    if ($remaining -ne 0) { throw "Split-Path null argument remains after repair: $remaining" }

    Write-Host "$PackageTag Reexecutando runner original: $TargetRunner"
    Push-Location $TargetRoot
    try {
        & $TargetRunner 2>&1 | Tee-Object -FilePath $resultLog
        $runnerExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($runnerExitCode -ne 0) {
        throw "original runner failed exit_code=$runnerExitCode log=$resultLog"
    }

    Write-Host "$PackageTag RUNNER PASSED. Log=$resultLog"
}
catch {
    Copy-Item -LiteralPath $scriptBackup -Destination $TargetScript -Force
    if ($null -ne $manifestBackup -and (Test-Path -LiteralPath $manifestBackup -PathType Leaf)) {
        Copy-Item -LiteralPath $manifestBackup -Destination $TargetManifest -Force
    }
    Write-Host "$PackageTag Emergency rollback of target package scripts COMPLETED."
    throw
}
