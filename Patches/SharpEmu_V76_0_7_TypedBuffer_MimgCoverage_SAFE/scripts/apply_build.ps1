param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')

$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
$state = Get-V7607State $repo
if ($state -eq 'Divergent') { throw 'APPLY recusado: source divergente.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $patches "_SharpEmu_V76_0_7_PREVIOUS_FILES_$stamp"
$backupZip = Join-Path $patches "SharpEmu_V76_0_7_PREVIOUS_FILES_$stamp.zip"
$buildLog = Join-Path $patches "SharpEmu_V76_0_7_BUILD_$stamp.log"
$summary = Join-Path $patches "SharpEmu_V76_0_7_SUMMARY_$stamp.txt"
$resultZip = Join-Path $patches "SharpEmu_V76_0_7_RESULT_$stamp.zip"
$didApply = $false

function Restore-Backup {
    if (-not $didApply) { return }
    foreach ($rel in $AffectedFiles) {
        $source = Join-Path $backupDir $rel
        $destination = Join-Path $repo $rel
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
}

try {
    if ($state -eq 'Ready') {
        foreach ($rel in $AffectedFiles) {
            $source = Join-Path $repo $rel
            $backupPath = Join-Path $backupDir $rel
            $backupParent = Split-Path -Parent $backupPath
            New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $backupPath -Force
        }
        Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
        Write-Host "[$PackageTag] Backup=$backupZip"

        # Backup is complete; from this point any partial copy must roll back.
        $didApply = $true
        foreach ($rel in $AffectedFiles) {
            $payload = Join-Path (Join-Path $PackageRoot 'payload') $rel
            $destination = Join-Path $repo $rel
            Copy-Item -LiteralPath $payload -Destination $destination -Force
        }
    }
    else {
        Write-Host "[$PackageTag] Payload ja aplicado; executando verify + build."
    }

    Assert-V7607Installed $repo
    Write-Host "[$PackageTag] APPLY VERIFY PASSED."

    $project = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building $project (Release / win-x64)..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit = $LASTEXITCODE
    if ($buildExit -ne 0) {
        Restore-Backup
        @(
            "Tag=$PackageTag",
            'Status=BUILD_FAILED_ROLLBACK',
            "ExitCode=$buildExit",
            "Backup=$backupZip",
            "BuildLog=$buildLog"
        ) | Set-Content -LiteralPath $summary -Encoding UTF8
        if (Test-Path -LiteralPath $resultZip) { Remove-Item -LiteralPath $resultZip -Force }
        Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
        throw "BUILD FAILED; rollback concluido. Resultado: $resultZip"
    }

    Assert-V7607Installed $repo
    @(
        "Tag=$PackageTag",
        'Status=BUILD_PASSED',
        "RepositoryRoot=$repo",
        "Backup=$backupZip",
        "BuildLog=$buildLog",
        'Scope=GFX10 MTBUF 4-bit decode + D16 typed loads + instruction FORMAT + non-MinLod MIMG sample coverage',
        'TypedStores=decoded but explicit pending conversion (V76.0.8)'
    ) | Set-Content -LiteralPath $summary -Encoding UTF8
    if (Test-Path -LiteralPath $resultZip) { Remove-Item -LiteralPath $resultZip -Force }
    Compress-Archive -LiteralPath $summary,$buildLog -DestinationPath $resultZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] BUILD PASSED."
    Write-Host "[$PackageTag] Summary=$summary"
    Write-Host "[$PackageTag] Result=$resultZip"
}
catch {
    if ($didApply) {
        try { Restore-Backup } catch { Write-Warning "Rollback secundario falhou: $($_.Exception.Message)" }
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $backupDir -PathType Container) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
