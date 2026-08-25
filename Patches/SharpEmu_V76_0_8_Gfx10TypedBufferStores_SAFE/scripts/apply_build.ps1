param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')

$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
$state = Get-V7608State $repo
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $patches "_SharpEmu_V76_0_8_PREVIOUS_FILES_$stamp"
$backupZip = Join-Path $patches "SharpEmu_V76_0_8_PREVIOUS_FILES_$stamp.zip"
$buildLog = Join-Path $patches "SharpEmu_V76_0_8_BUILD_$stamp.log"
$summary = Join-Path $patches "SharpEmu_V76_0_8_SUMMARY_$stamp.txt"
$resultZip = Join-Path $patches "SharpEmu_V76_0_8_RESULT_$stamp.zip"
$didMutate = $false
$rollbackCompleted = $false
$helperExistedBefore = Test-Path -LiteralPath (Join-Path $repo $HelperRel) -PathType Leaf

function Restore-Backup {
    foreach ($rel in $AffectedExistingFiles) {
        $source = Join-Path $backupDir $rel
        $destination = Join-Path $repo $rel
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    $helperBackup = Join-Path $backupDir $HelperRel
    $helperTarget = Join-Path $repo $HelperRel
    if ($helperExistedBefore) {
        if (Test-Path -LiteralPath $helperBackup -PathType Leaf) {
            Copy-Item -LiteralPath $helperBackup -Destination $helperTarget -Force
        }
    }
    elseif (Test-Path -LiteralPath $helperTarget -PathType Leaf) {
        Remove-Item -LiteralPath $helperTarget -Force
    }
}

try {
    if ($state -ne 'AlreadyApplied') {
        foreach ($rel in $AffectedExistingFiles) {
            $source = Join-Path $repo $rel
            $backupPath = Join-Path $backupDir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $backupPath -Force
        }
        if ($helperExistedBefore) {
            $source = Join-Path $repo $HelperRel
            $backupPath = Join-Path $backupDir $HelperRel
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $backupPath -Force
        }
        Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
        Write-Host "[$PackageTag] Backup=$backupZip"

        # Backup completed before the first write. Any exception from this point
        # is eligible for rollback, including a missing dotnet executable.
        $didMutate = $true
        & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    }
    else {
        Write-Host "[$PackageTag] V76.0.8 ja aplicada; executando verify + build."
    }

    Assert-V7608Installed $repo
    Write-Host "[$PackageTag] APPLY VERIFY PASSED."

    $project = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building $project (Release / win-x64)..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit = $LASTEXITCODE
    if ($buildExit -ne 0) {
        if ($didMutate) {
            Restore-Backup
            $rollbackCompleted = $true
        }
        @(
            "Tag=$PackageTag",
            'Status=BUILD_FAILED_ROLLBACK',
            "ExitCode=$buildExit",
            "Backup=$backupZip",
            "BuildLog=$buildLog",
            'ApplyMode=adaptive-in-place'
        ) | Set-Content -LiteralPath $summary -Encoding UTF8
        if (Test-Path -LiteralPath $resultZip) { Remove-Item -LiteralPath $resultZip -Force }
        Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
        throw "BUILD FAILED; rollback concluido. Resultado: $resultZip"
    }

    Assert-V7608Installed $repo
    @(
        "Tag=$PackageTag",
        'Status=BUILD_PASSED',
        "RepositoryRoot=$repo",
        "InitialState=$state",
        "Backup=$backupZip",
        "BuildLog=$buildLog",
        'ApplyMode=adaptive-in-place; no whole-file replacement',
        'MubufOpcodeWidth=8-bit; D16 0x80..0x87 decoded',
        'TypedStores=MTBUF instruction FORMAT + identity; MUBUF resource FORMAT + resource dst_sel',
        'D16Stores=packed low/high half source components',
        'FormatConversion=UNORM/SNORM/USCALED/SSCALED/UINT/SINT/FLOAT including 10/11-bit UFLOAT',
        'D16LoadIntegerKindFix=Equal(numberFormat,4/5) numeric constants'
    ) | Set-Content -LiteralPath $summary -Encoding UTF8
    if (Test-Path -LiteralPath $resultZip) { Remove-Item -LiteralPath $resultZip -Force }
    Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] BUILD PASSED."
    Write-Host "[$PackageTag] Summary=$summary"
    Write-Host "[$PackageTag] Result=$resultZip"
}
catch {
    if ($didMutate -and -not $rollbackCompleted) {
        try {
            Restore-Backup
            $rollbackCompleted = $true
            Write-Host "[$PackageTag] Emergency rollback COMPLETED." -ForegroundColor Yellow
        }
        catch {
            Write-Warning "Rollback secundario falhou: $($_.Exception.Message)"
        }
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $backupDir -PathType Container) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
