param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot "common.ps1")

& (Join-Path $PSScriptRoot "validate_package.ps1")

$root = Resolve-SharpEmuRepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$target = Get-ApplyTarget $root
$text = Read-Utf8Text $target
$normalized = Normalize-Lf $text
$didPatch = $false
$backup = $null
$backupRoot = $null

if ($normalized.Contains("V61.22.0 WRITE_DATA active-wait latch")) {
    Write-Host "[V61.22.0] Already applied; proceeding to build." -ForegroundColor Yellow
} else {
    $useCrLf = $text.Contains("`r`n")
    $old = Normalize-Lf (Get-OldWriteDataBlock)
    $new = Normalize-Lf (Get-NewWriteDataBlock)
    $index = $normalized.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($index -lt 0) { throw "Apply aborted: expected WRITE_DATA block not found after precheck." }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot = Join-Path $root ".sharpemu-hotfix-backup\V61_22_0_$stamp"
    $backup = Join-Path $backupRoot "src\SharpEmu.Libs\Agc\AgcExports.cs"
    New-Item -ItemType Directory -Force -Path (Split-Path $backup -Parent) | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Force

    $patched = $normalized.Substring(0, $index) + $new + $normalized.Substring($index + $old.Length)
    $patched = Restore-Newlines $patched $useCrLf
    Write-Utf8NoBom -Path $target -Text $patched

    $verify = Normalize-Lf (Read-Utf8Text $target)
    if (-not $verify.Contains("V61.22.0 WRITE_DATA active-wait latch") -or
        -not $verify.Contains("agc.write_data_wait_latched")) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        throw "Post-apply verification failed; source restored from backup."
    }

    $didPatch = $true
    Write-Host "[V61.22.0] Patch applied." -ForegroundColor Green
    Write-Host "[V61.22.0] Backup: $backupRoot"
}

$buildFailed = $false
Push-Location $root
try {
    Write-Host "[V61.22.0] Building SharpEmu.slnx (Debug)..." -ForegroundColor Cyan
    & dotnet build ".\SharpEmu.slnx" -c Debug --nologo
    if ($LASTEXITCODE -ne 0) {
        $buildFailed = $true
    }
} finally {
    Pop-Location
}

if ($buildFailed) {
    if ($didPatch -and $null -ne $backup -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Write-Host "[V61.22.0] Build failed; source restored from backup." -ForegroundColor Yellow
    }
    throw "dotnet build failed."
}

Write-Host "[V61.22.0] SUCCESS" -ForegroundColor Green
Write-Host "[V61.22.0] WRITE_DATA now latches only labels that are actively awaited."
Write-Host "[V61.22.0] Next: RUN_DEMONS_DIAGNOSTIC_V61_22_0.cmd"
