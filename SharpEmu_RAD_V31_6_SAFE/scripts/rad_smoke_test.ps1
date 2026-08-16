param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Movie="F:\JOGOSPS5\PPSA01341\movies\ps_studios_logo.bk2",
    [int]$TimeoutSeconds=45)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch

if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.6] RAD REQUIRED: radvideo64.exe not found."
}
if (-not (Test-Path -LiteralPath $Movie -PathType Leaf)) {
    throw "[V72.4.3.2.31.6] Smoke-test movie not found: $Movie"
}
if ($Movie.Contains('"')) {
    throw "[V72.4.3.2.31.6] Unsupported quote in movie path."
}

Write-Host "[V72.4.3.2.31.6] RAD BinkPlay standalone smoke test." -ForegroundColor Cyan
Write-Host ("[V72.4.3.2.31.6] RAD=" + $rad)
Write-Host ("[V72.4.3.2.31.6] MOVIE=" + $Movie)
Write-Host "[V72.4.3.2.31.6] COMMAND=radvideo64.exe binkplay <movie>"
Write-Host "[V72.4.3.2.31.6] There must be NO BinkPlay syntax/help dialog."

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $rad
$psi.Arguments = 'binkplay "' + $Movie + '"'
$psi.WorkingDirectory = Split-Path -Parent $rad
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$watch = [Diagnostics.Stopwatch]::StartNew()

if (-not $proc.Start()) {
    throw "[V72.4.3.2.31.6] Failed to start RAD BinkPlay."
}

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    throw "[V72.4.3.2.31.6] RAD BinkPlay did not exit within $TimeoutSeconds seconds."
}

$watch.Stop()
$exitCode = $proc.ExitCode
$proc.Dispose()

Write-Host ("[V72.4.3.2.31.6] RAD_SMOKE_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2))
Write-Host ("[V72.4.3.2.31.6] RAD_SMOKE_EXIT_CODE=" + $exitCode)

if ($exitCode -ne 0) {
    throw "[V72.4.3.2.31.6] RAD BinkPlay smoke test failed with exit code $exitCode. Do not run the emulator test."
}

Write-Host "[V72.4.3.2.31.6] RAD BINKPLAY SMOKE TEST PASSED." -ForegroundColor Green
