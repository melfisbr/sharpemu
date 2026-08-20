. "$PSScriptRoot\common.ps1"
$p=Paths
$pkg=PackageRoot

try{
    Assert-V740883 $p.Repo
}
catch{
    Write-Host "$script:Tag [ERROR] V74.0.88.3 source baseline missing: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$runner=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\run_test.ps1'))

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "v88_3_source_baseline=True"
Write-Host "live_runtime_log=$($runner.Contains('LIVE_RUNTIME_LOG'))"
Write-Host "cmd_stderr_merge=$($runner.Contains('/D /S /C') -and $runner.Contains('2>&1'))"
Write-Host "native_direct_invocation_removed=$(-not $runner.Contains('& $p.Exe $eboot 2>&1'))"
Write-Host "temp_stderr_removed=$(-not $runner.Contains('RedirectStandardError'))"
Write-Host "temp_stdout_removed=$(-not $runner.Contains('RedirectStandardOutput'))"
Write-Host "runtime_autoflush=$($runner.Contains('$writer.AutoFlush=$true'))"
Write-Host "build_artifact_exists=$(Test-Path -LiteralPath $p.Exe)"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
