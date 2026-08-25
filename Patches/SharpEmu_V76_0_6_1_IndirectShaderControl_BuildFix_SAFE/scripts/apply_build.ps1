param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
& (Join-Path $PSScriptRoot 'validate.ps1')
$state = Get-V7606State $repo
if ($state -eq 'Partial') { throw 'APPLY recusado: V76.0.6/6.1 parcialmente presente.' }
if ($state -eq 'AlreadyApplied') {
    Assert-V7606Installed $repo
    Write-Host "[$PackageTag] V76.0.6.1 already applied; building verification only."
}

Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupZip = Join-Path $patches "SharpEmu_V76_0_6_1_PREVIOUS_FILES_$stamp.zip"
$buildLog = Join-Path $patches "SharpEmu_V76_0_6_1_BUILD_$stamp.log"
$summaryPath = Join-Path $patches "SharpEmu_V76_0_6_1_SUMMARY_$stamp.txt"
$resultZip = Join-Path $patches "SharpEmu_V76_0_6_1_RESULT_$stamp.zip"
$tempRoot = Join-Path $env:TEMP "SharpEmu_V76_0_6_1_$stamp"
$backupRoot = Join-Path $tempRoot 'backup'
$resultRoot = Join-Path $tempRoot 'result'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null

$mayChange = @($TranslatorRel,$EvaluatorRel,$IndirectHelperRel)
$backedUp = New-Object System.Collections.Generic.List[string]
$added = New-Object System.Collections.Generic.List[string]
$sourceMutated = $false
$buildPassed = $false
$rollbackCompleted = $false
try {
    foreach ($rel in $mayChange) {
        $target = Join-Path $repo $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $backupFile = Join-Path $backupRoot $rel
            $dir = Split-Path -Parent $backupFile
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupFile -Force
            $backedUp.Add($rel)
        } else { $added.Add($rel) }
    }
    if ($backedUp.Count -gt 0) {
        Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
        Write-Host "[$PackageTag] Backup=$backupZip"
    }

    if ($state -ne 'AlreadyApplied') {
        $helperSource = Join-Path $PackageRoot ('payload\' + $IndirectHelperRel)
        $helperTarget = Join-Path $repo $IndirectHelperRel
        New-Item -ItemType Directory -Path (Split-Path -Parent $helperTarget) -Force | Out-Null
        Copy-Item -LiteralPath $helperSource -Destination $helperTarget -Force
        $sourceMutated = $true
        & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    }
    Assert-V7606Installed $repo
    Write-Host "[$PackageTag] APPLY VERIFY PASSED."

    $project = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building $project (Release / win-x64)..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit = $LASTEXITCODE

    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add("Tag=$PackageTag")
    $summary.Add("RepositoryRoot=$repo")
    $summary.Add("InitialState=$state")
    $summary.Add("BuildExitCode=$buildExit")
    $summary.Add("BuildLog=$buildLog")
    $summary.Add("Backup=$backupZip")
    $summary.Add('Core=S_SETPC_B64; S_SWAPPC_B64; indirect CFG; scalar call/return discovery; S_ASHR_I64 evaluator; CS0136/CS0165 buildfix')
    $summary.Add('Scope=shader translator/evaluator only; no RAD/IME/DCC/presenter/scheduler changes')

    if ($buildExit -ne 0) {
        $summary.Add('Build=FAILED'); $summary.Add('Rollback=STARTED')
        foreach ($rel in $backedUp) { Copy-Item -LiteralPath (Join-Path $backupRoot $rel) -Destination (Join-Path $repo $rel) -Force }
        foreach ($rel in $added) { $target=Join-Path $repo $rel; if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force } }
        $rollbackCompleted = $true; $summary.Add('Rollback=COMPLETED')
        Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8
        Copy-Item $summaryPath $resultRoot -Force
        if (Test-Path $buildLog) { Copy-Item $buildLog $resultRoot -Force }
        Compress-Archive -Path (Join-Path $resultRoot '*') -DestinationPath $resultZip -CompressionLevel Optimal -Force
        throw "BUILD FAILED; rollback concluido. Resultado: $resultZip"
    }

    $buildPassed = $true
    $summary.Add('Build=PASSED'); $summary.Add('Rollback=NOT_REQUIRED')
    Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8
    Copy-Item $summaryPath $resultRoot -Force; Copy-Item $buildLog $resultRoot -Force
    Compress-Archive -Path (Join-Path $resultRoot '*') -DestinationPath $resultZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] BUILD PASSED."
    Write-Host "[$PackageTag] Summary=$summaryPath"
    Write-Host "[$PackageTag] Result=$resultZip"
}
catch {
    if ($sourceMutated -and -not $buildPassed -and -not $rollbackCompleted) {
        Write-Host "[$PackageTag] Exception depois do primeiro write; restaurando source..." -ForegroundColor Yellow
        foreach ($rel in $backedUp) { $src=Join-Path $backupRoot $rel; if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $repo $rel) -Force } }
        foreach ($rel in $added) { $target=Join-Path $repo $rel; if (Test-Path $target) { Remove-Item -LiteralPath $target -Force } }
        $rollbackCompleted = $true
        Write-Host "[$PackageTag] Emergency rollback COMPLETED." -ForegroundColor Yellow
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
