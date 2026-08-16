. "$PSScriptRoot\common.ps1"

$repo = Get-RepoRoot
$imports = Join-Path $repo $Script:ImportsRelative
$trace = Join-Path $repo $Script:TraceRelative
$v173 = Join-Path $repo $Script:V173Relative

if (-not (Test-Path -LiteralPath $Script:GamePath)) {
    throw "DBFZ eboot missing: $Script:GamePath"
}

$hash = (Get-FileHash -LiteralPath $Script:GamePath -Algorithm SHA256).Hash.ToLowerInvariant()

if ($hash -ne $Script:ExpectedEbootSha) {
    throw "Unexpected DBFZ eboot SHA256: $hash"
}

foreach ($required in @($imports, $trace, $v173)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required source missing: $required"
    }
}

$importsText = [System.IO.File]::ReadAllText($imports)
$traceText = [System.IO.File]::ReadAllText($trace)
$v173Text = [System.IO.File]::ReadAllText($v173)

$oldCount = ([regex]::Matches(
    $importsText,
    [regex]::Escape($Script:OldBoundary))).Count

$newCount = ([regex]::Matches(
    $importsText,
    [regex]::Escape($Script:NewBoundary))).Count

$markerCount = ([regex]::Matches(
    $importsText,
    [regex]::Escape($Script:Marker))).Count

if ($oldCount -gt 1 -or $newCount -gt 1 -or $markerCount -gt 1) {
    throw "Import-loop boundary state is ambiguous."
}

if ($oldCount -eq 0 -and $newCount -eq 0) {
    throw "Expected IsImportLoopGuardBoundary source block was not found."
}

if (-not $traceText.Contains("TraceDragonBallFighterZAprReadFile")) {
    throw "APR trace prerequisite helper missing."
}

if (-not $v173Text.Contains("SHARPEMU_DBFZ_GETDENTS_BATCH_V1_7_3")) {
    throw "V1.7.3 prerequisite marker missing."
}

Write-Host "[DBFZ-ILU-176] Repository: $repo"
Write-Host "[DBFZ-ILU-176] EbootSHA256=$hash"
Write-Host "[DBFZ-ILU-176] OldBoundaryCount=$oldCount"
Write-Host "[DBFZ-ILU-176] NewBoundaryCount=$newCount"
Write-Host "[DBFZ-ILU-176] MarkerCount=$markerCount"
Write-Host "[DBFZ-ILU-176] GlobalLoopGuardStillEnabled=True"

if ($newCount -eq 1 -and $markerCount -eq 1) {
    Write-Host "[DBFZ-ILU-176] State=AlreadyApplied"
}
else {
    Write-Host "[DBFZ-ILU-176] State=ReadyToApply"
}

Write-Host "[DBFZ-ILU-176] PRECHECK PASSED."
