param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot

& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$text = [IO.File]::ReadAllText($target)
$changed = $false
$backup = $null

$methodAnchor = 'public static void Register(ulong address, WaitingDcb waiter)'
$methodStart = $text.IndexOf($methodAnchor, [StringComparison]::Ordinal)
$lockPos = $text.IndexOf('lock (_gate)', $methodStart, [StringComparison]::Ordinal)
$lockBrace = $text.IndexOf('{', $lockPos)
$nextOriginal = 'if (!_waiters.TryGetValue(address, out var list))'
$originalPos = $text.IndexOf($nextOriginal, $lockBrace, [StringComparison]::Ordinal)
$markerPos = $text.IndexOf('V61.23.1 label generation reset', $lockBrace, [StringComparison]::Ordinal)
$removePos = $text.IndexOf('_lastProduced.Remove((waiter.Memory, address))', $lockBrace, [StringComparison]::Ordinal)

$active = $markerPos -ge 0 -and $markerPos -lt $originalPos -and
          $removePos -ge 0 -and $removePos -lt $originalPos

if ($active) {
    # V61.23.1 was inserted at lockBrace+1. Preserve the lock brace and the
    # original waiter-list statement, replacing only the injected interval.
    $removeStart = $lockBrace + 1
    $removeLength = $originalPos - $removeStart
    if ($removeLength -le 0 -or $removeLength -gt 6000) {
        throw "APPLY ERROR: unsafe injected interval length=$removeLength."
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $root ".sharpemu-hotfix-backup\V61_23_5_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backup = Join-Path $backupDir 'GpuWaitRegistry.cs'
    Copy-Item -LiteralPath $target -Destination $backup

    $indent = '            '
    $replacement = "`r`n$indent// V61.23.5: V61.23.1 eager epoch deletion removed; preserve producer history until a real producer updates it.`r`n            "
    $newText = $text.Remove($removeStart, $removeLength).Insert($removeStart, $replacement)

    # Strong post-transform checks before writing.
    $newMethodStart = $newText.IndexOf($methodAnchor, [StringComparison]::Ordinal)
    $newLockPos = $newText.IndexOf('lock (_gate)', $newMethodStart, [StringComparison]::Ordinal)
    $newOriginalPos = $newText.IndexOf($nextOriginal, $newLockPos, [StringComparison]::Ordinal)
    if ($newOriginalPos -lt 0) { throw 'APPLY ERROR: original waiter-list statement lost.' }
    if ($newText.Contains('V61.23.1 label generation reset')) {
        throw 'APPLY ERROR: V61.23.1 marker survived structural rollback.'
    }
    if ($newText.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
        throw 'APPLY ERROR: eager _lastProduced removal survived structural rollback.'
    }

    [IO.File]::WriteAllText($target, $newText, [Text.UTF8Encoding]::new($false))
    $changed = $true
    Write-Host "[V61.23.5] Structural rollback applied. Backup: $backupDir"
}
else {
    Write-Host '[V61.23.5] Eager epoch block already absent; no source edit required.'
}

try {
    Push-Location $root
    try {
        & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
        if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Libs build failed: $LASTEXITCODE" }

        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed: $LASTEXITCODE" }
    }
    finally { Pop-Location }
}
catch {
    if ($changed -and $null -ne $backup -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Write-Host '[V61.23.5] Build failed; source restored automatically.' -ForegroundColor Yellow
    }
    throw
}

$final = [IO.File]::ReadAllText($target)
if ($final.Contains('V61.23.1 label generation reset') -or
    $final.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
    throw 'POSTCHECK ERROR: V61.23.1 eager epoch logic still active.'
}

Write-Host '[V61.23.5] SUCCESS'
Write-Host '[V61.23.5] Eager label-history deletion removed.'
Write-Host '[V61.23.5] Real WRITE_DATA/DMA/RELEASE_MEM producer tracking preserved.'
Write-Host '[V61.23.5] Next: RUN_DEMONS_DIAGNOSTIC_V61_23_5.cmd'
