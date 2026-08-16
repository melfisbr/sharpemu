. "$PSScriptRoot\common.ps1"

& "$PSScriptRoot\validate.ps1"
& "$PSScriptRoot\precheck.ps1"

$repo = Get-RepoRoot
$imports = Join-Path $repo $Script:ImportsRelative

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot = Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_ImportLoopUnlockBoundary_V1_7_6_" + $stamp)

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
Copy-Item -LiteralPath $imports -Destination (Join-Path $backupRoot "DirectExecutionBackend.Imports.cs") -Force

try {
    $text = [System.IO.File]::ReadAllText($imports)

    if (-not $text.Contains($Script:Marker)) {
        $oldCount = ([regex]::Matches(
            $text,
            [regex]::Escape($Script:OldBoundary))).Count

        if ($oldCount -ne 1) {
            throw "Expected exactly one old loop-boundary block; found $oldCount."
        }

        $text = $text.Replace(
            $Script:OldBoundary,
            $Script:NewBoundary)

        [System.IO.File]::WriteAllText(
            $imports,
            $text,
            (Get-Utf8NoBom))

        Write-Host "[DBFZ-ILU-176] Added mutex/rwlock unlocks as loop-guard progress boundaries."
    }
    else {
        Write-Host "[DBFZ-ILU-176] Unlock boundary marker already present."
    }

    $verify = [System.IO.File]::ReadAllText($imports)

    $newCount = ([regex]::Matches(
        $verify,
        [regex]::Escape($Script:NewBoundary))).Count

    if ($newCount -ne 1 -or
        -not $verify.Contains($Script:Marker)) {
        throw "Post-apply V1.7.6 boundary verification failed."
    }

    if (-not $verify.Contains("SHARPEMU_DISABLE_IMPORT_LOOP_GUARD")) {
        throw "Global import-loop guard configuration disappeared unexpectedly."
    }

    Write-Host "[DBFZ-ILU-176] Structural boundary validation PASSED."
    Write-Host "[DBFZ-ILU-176] Global import-loop guard remains enabled."
    Write-Host "[DBFZ-ILU-176] Building SharpEmu.CLI Debug..."

    & dotnet build ".\src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug --nologo

    if ($LASTEXITCODE -ne 0) {
        throw "SharpEmu.CLI build failed."
    }

    Write-Host "[DBFZ-ILU-176] APPLY/BUILD PASSED."
    Write-Host "[DBFZ-ILU-176] Backup: $backupRoot"
}
catch {
    Write-Host "[DBFZ-ILU-176] Failure detected; restoring source backup."
    Copy-Item -LiteralPath (Join-Path $backupRoot "DirectExecutionBackend.Imports.cs") -Destination $imports -Force
    throw
}
