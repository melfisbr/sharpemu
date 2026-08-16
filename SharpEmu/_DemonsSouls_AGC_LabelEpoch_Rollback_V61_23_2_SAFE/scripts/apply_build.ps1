param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$target=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$text=[IO.File]::ReadAllText($target)
if ($text.Contains('V61.23.2 rollback of eager label generation reset')) {
    Write-Host '[V61.23.2] Source already rolled back; building.'
} else {
    $start=$text.IndexOf('            // V61.23.1 label generation reset:', [StringComparison]::Ordinal)
    if ($start -lt 0) { throw 'APPLY ERROR: V61.23.1 block start not found.' }
    $endNeedle='            }'
    # Find the end of the outer "if (waiter.Memory is not null)" block by locating
    # the marker's Console.Error section and then the next outer closing brace.
    $console=$text.IndexOf('Console.Error.WriteLine(', $start, [StringComparison]::Ordinal)
    if ($console -lt 0) { throw 'APPLY ERROR: V61.23.1 trace body not found.' }
    $pos=$console
    $closeCount=0
    while ($pos -lt $text.Length) {
        $nl=$text.IndexOf("`n",$pos)
        if ($nl -lt 0) { $nl=$text.Length }
        $line=$text.Substring($pos,$nl-$pos).Trim()
        if ($line -eq '}') {
            $closeCount++
            if ($closeCount -eq 2) { $blockEnd=$nl+1; break }
        }
        $pos=$nl+1
    }
    if ($null -eq $blockEnd) { throw 'APPLY ERROR: V61.23.1 block end not found.' }

    $replacement=@"
            // V61.23.2 rollback of eager label generation reset:
            // Do not delete _lastProduced merely because Register() sees a new
            // unsatisfied waiter. V61.23.1 proved this is too broad: many valid
            // cross-queue labels are re-armed before their producer executes.
            // Producer history remains fail-closed and is updated only by real
            // WRITE_DATA/DMA/RELEASE_MEM production paths.

"@
    $newText=$text.Substring(0,$start)+$replacement+$text.Substring($blockEnd)
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir=Join-Path $root ".sharpemu-hotfix-backup\V61_23_2_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $target -Destination (Join-Path $backupDir 'GpuWaitRegistry.cs')
    [IO.File]::WriteAllText($target,$newText,[Text.UTF8Encoding]::new($false))
    Write-Host "[V61.23.2] Backup: $backupDir"
}

Push-Location $root
try {
    & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
    if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Libs build failed: $LASTEXITCODE" }
    & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
    if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed: $LASTEXITCODE" }
} finally { Pop-Location }
Write-Host '[V61.23.2] SUCCESS'
Write-Host '[V61.23.2] Eager epoch deletion removed; real producer tracking preserved.'
