param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root
$target=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$text=[IO.File]::ReadAllText($target)
if ($text.Contains('V61.23.0 label generation reset')) {
    Write-Host '[V61.23.0] Source already patched; proceeding to build.'
} else {
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir=Join-Path $root ".sharpemu-hotfix-backup\V61_23_0_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backup=Join-Path $backupDir 'GpuWaitRegistry.cs'
    Copy-Item -LiteralPath $target -Destination $backup

    # Insert the epoch reset inside Register(), immediately after taking _gate.
    $methodStart=$text.IndexOf('public static void Register(ulong address, WaitingDcb waiter)',[StringComparison]::Ordinal)
    if ($methodStart -lt 0) { throw 'APPLY ERROR: Register method not found.' }
    $lockPos=$text.IndexOf('lock (_gate)',$methodStart,[StringComparison]::Ordinal)
    if ($lockPos -lt 0) { throw 'APPLY ERROR: Register lock not found.' }
    $bracePos=$text.IndexOf('{',$lockPos)
    if ($bracePos -lt 0) { throw 'APPLY ERROR: Register lock brace not found.' }
    $insert=@"

            // V61.23.0 label generation reset: Register() is reached only for an
            // unsatisfied wait. A value produced before this registration belongs
            // to an older guest label generation (the guest has reset/re-armed the
            // address), so it must never justify releasing this new waiter later.
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
    $newText=$text.Insert($bracePos+1,$insert)
    [IO.File]::WriteAllText($target,$newText,[Text.UTF8Encoding]::new($false))

    try {
        Push-Location $root
        try {
            dotnet build .\src\SharpEmu.Libs\SharpEmu.Libs.csproj -c Debug --nologo
            if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Libs build failed with exit code $LASTEXITCODE" }
            dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
            if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed with exit code $LASTEXITCODE" }
        } finally { Pop-Location }
    } catch {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Write-Host '[V61.23.0] Build failed; GpuWaitRegistry.cs restored automatically.' -ForegroundColor Yellow
        throw
    }
    Write-Host "[V61.23.0] Backup: $backupDir"
}
Write-Host '[V61.23.0] SUCCESS'
Write-Host '[V61.23.0] Label generations now invalidate stale _lastProduced history on unsatisfied wait registration.'
Write-Host '[V61.23.0] No wait is force-satisfied.'
Write-Host '[V61.23.0] Next: RUN_DEMONS_DIAGNOSTIC_V61_23_0.cmd'
