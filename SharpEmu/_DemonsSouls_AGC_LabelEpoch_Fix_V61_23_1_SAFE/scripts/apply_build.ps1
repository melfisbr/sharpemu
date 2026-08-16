param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$text = [IO.File]::ReadAllText($target)
if ($text.Contains('V61.23.1 label generation reset')) {
    Write-Host '[V61.23.1] Source already patched; proceeding to build.'
} else {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $root ".sharpemu-hotfix-backup\V61_23_1_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backup = Join-Path $backupDir 'GpuWaitRegistry.cs'
    Copy-Item -LiteralPath $target -Destination $backup

    $methodAnchor = 'public static void Register(ulong address, WaitingDcb waiter)'
    $methodStart = $text.IndexOf($methodAnchor, [StringComparison]::Ordinal)
    if ($methodStart -lt 0) { throw 'APPLY ERROR: Register method not found.' }
    $lockPos = $text.IndexOf('lock (_gate)', $methodStart, [StringComparison]::Ordinal)
    if ($lockPos -lt 0 -or ($lockPos - $methodStart) -gt 3000) { throw 'APPLY ERROR: Register lock not found.' }
    $bracePos = $text.IndexOf('{', $lockPos)
    if ($bracePos -lt 0) { throw 'APPLY ERROR: Register lock brace not found.' }

    $insert = @"

            // V61.23.1 label generation reset: Register() is reached for a wait
            // that is not currently satisfied. Any last-produced value retained
            // for this address belongs to an older arm/reset cycle and must not be
            // used by the deadlock breaker as evidence for this new waiter.
            if (waiter.Memory is not null)
            {
                var removedPreviousGeneration = _lastProduced.Remove((waiter.Memory, address));
                if (removedPreviousGeneration &&
                    string.Equals(
                        Environment.GetEnvironmentVariable("SHARPEMU_LOG_AGC_EPOCH"),
                        "1",
                        StringComparison.Ordinal))
                {
                    Console.Error.WriteLine(
                        $"[LOADER][TRACE] agc.label_epoch_reset label=0x{address:X16} " +
                        $"queue={waiter.QueueName} submission={waiter.SubmissionId}");
                }
            }
"@
    $newText = $text.Insert($bracePos + 1, $insert)
    [IO.File]::WriteAllText($target, $newText, [Text.UTF8Encoding]::new($false))

    try {
        Push-Location $root
        try {
            & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
            if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Libs build failed with exit code $LASTEXITCODE" }
            & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
            if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed with exit code $LASTEXITCODE" }
        } finally { Pop-Location }
    } catch {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Write-Host '[V61.23.1] Build failed; GpuWaitRegistry.cs restored automatically.' -ForegroundColor Yellow
        throw
    }
    Write-Host "[V61.23.1] Backup: $backupDir"
}
Write-Host '[V61.23.1] SUCCESS'
Write-Host '[V61.23.1] Stale deadlock-history is invalidated when a new unsatisfied label generation is registered.'
Write-Host '[V61.23.1] No wait is force-satisfied.'
Write-Host '[V61.23.1] Next: RUN_DEMONS_DIAGNOSTIC_V61_23_1.cmd'
