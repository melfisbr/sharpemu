param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot

& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$text = [IO.File]::ReadAllText($target)
$changed = $false
$backup = $null
$backupDir = $null

if ($text.Contains('V61.23.1 label generation reset')) {
    $oldBlock = @'
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
'@

    # Accept CRLF or LF source by normalizing only for locating the exact block.
    $normalizedText = $text.Replace("`r`n", "`n")
    $normalizedOld = $oldBlock.Replace("`r`n", "`n")
    $idx = $normalizedText.IndexOf($normalizedOld, [StringComparison]::Ordinal)
    if ($idx -lt 0) {
        throw 'APPLY ERROR: V61.23.1 marker exists but exact inserted block was not found.'
    }

    # Map normalized character position back safely by using a regex created from
    # the exact normalized lines with optional CR before each LF.
    $escaped = [regex]::Escape($normalizedOld)
    $pattern = $escaped.Replace('\\\n', '\r?\n')
    $regex = [regex]::new($pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    $matches = $regex.Matches($text)
    if ($matches.Count -ne 1) {
        throw "APPLY ERROR: expected exactly one V61.23.1 block; found $($matches.Count)."
    }

    $replacement = @'
            // V61.23.4 rollback of eager label generation reset:
            // Registering a new unsatisfied waiter is not sufficient evidence
            // that the previous producer history is stale. Cross-queue work can
            // legitimately re-arm the same label before the producer executes.
            // Keep _lastProduced fail-closed and update it only from real
            // WRITE_DATA/DMA/RELEASE_MEM producer completion paths.
'@

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $root ".sharpemu-hotfix-backup\V61_23_4_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backup = Join-Path $backupDir 'GpuWaitRegistry.cs'
    Copy-Item -LiteralPath $target -Destination $backup

    $newText = $regex.Replace($text, [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return $replacement
    }, 1)

    if ($newText.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
        throw 'APPLY ERROR: eager _lastProduced removal survived replacement.'
    }
    if ($newText.Contains('V61.23.1 label generation reset')) {
        throw 'APPLY ERROR: V61.23.1 marker survived replacement.'
    }

    [IO.File]::WriteAllText($target, $newText, [Text.UTF8Encoding]::new($false))
    $changed = $true
    Write-Host "[V61.23.4] Exact V61.23.1 block removed. Backup: $backupDir"
} else {
    Write-Host '[V61.23.4] Eager epoch block already absent; no source edit required.'
}

try {
    Push-Location $root
    try {
        & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
        if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Libs build failed: $LASTEXITCODE" }

        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed: $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}
catch {
    if ($changed -and $null -ne $backup -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Write-Host '[V61.23.4] Build failed; GpuWaitRegistry.cs restored automatically.' -ForegroundColor Yellow
    }
    throw
}

$final = [IO.File]::ReadAllText($target)
if ($final.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
    throw 'POSTCHECK ERROR: eager epoch deletion is still active after build.'
}

Write-Host '[V61.23.4] SUCCESS'
Write-Host '[V61.23.4] V61.23.1 eager label-history deletion is not active.'
Write-Host '[V61.23.4] Real PM4 producer tracking remains untouched.'
Write-Host '[V61.23.4] Next: RUN_DEMONS_DIAGNOSTIC_V61_23_4.cmd'
