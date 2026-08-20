. "$PSScriptRoot\common.ps1"
$s = Get-LauncherState
if ($s.OldCalls -gt 0 -or -not $s.Marker -or $s.NewCalls -lt 1) {
    throw "$script:Tag Launcher ainda nao esta corrigido. Execute RUN_3_APPLY_LAUNCHER_FIX.cmd primeiro."
}
Test-PowerShellParse $script:Target
$originalRun = Join-Path $script:TargetPackage 'RUN_5_TEST_DEMONS.cmd'
if (-not (Test-Path -LiteralPath $originalRun -PathType Leaf)) { throw "$script:Tag RUN_5 original nao encontrado: $originalRun" }
Write-Host "$script:Tag Iniciando o teste original V74.0.77.2 com launcher PowerShell 5.1 corrigido." -ForegroundColor Cyan
& $originalRun
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
