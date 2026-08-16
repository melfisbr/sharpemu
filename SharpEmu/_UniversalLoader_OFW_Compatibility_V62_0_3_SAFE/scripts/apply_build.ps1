param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepositoryRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$source = [IO.File]::ReadAllText($selfLoader)

$oldBlock = @'
        if (header.ProgramHeaderEntrySize != ProgramHeaderSize)
        {
            throw new InvalidDataException($"Unsupported ELF program header entry size: {header.ProgramHeaderEntrySize}.");
        }
'@

$newBlock = @'
        // V62.0.3 OFW_LOADER_COMPAT
        // Accept an ELF64 program-header record that extends the standard
        // leading prefix. ParseProgramHeaders uses the advertised stride.
        if (header.ProgramHeaderEntrySize < ProgramHeaderSize)
        {
            throw new InvalidDataException(
                $"ELF program header entry size {header.ProgramHeaderEntrySize} is smaller than the required {ProgramHeaderSize}-byte ELF64 prefix.");
        }
'@

$changed = $false
$backupPath = $null

if ($source.IndexOf($oldBlock, [StringComparison]::Ordinal) -ge 0) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDirectory = Join-Path $root ('.sharpemu-hotfix-backup\UniversalLoader_V62_0_3_{0}' -f $stamp)
    New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
    $backupPath = Join-Path $backupDirectory 'SelfLoader.cs'
    Copy-Item -LiteralPath $selfLoader -Destination $backupPath -Force

    $source = $source.Replace($oldBlock, $newBlock)
    [IO.File]::WriteAllText($selfLoader, $source, [Text.UTF8Encoding]::new($false))
    $changed = $true

    Write-Host ('[V62.0.3] Strict e_phentsize equality widened. Backup: {0}' -f $backupDirectory)
}
elseif (
    (Test-TextContains -Text $source -Pattern 'header.ProgramHeaderEntrySize < ProgramHeaderSize') -or
    (Test-TextContains -Text $source -Pattern 'ProgramHeaderEntrySize < ProgramHeaderSize')
) {
    Write-Host '[V62.0.3] e_phentsize is already minimum-size compatible; no duplicate source edit.'
}
else {
    Write-Host '[V62.0.3] Custom program-header validation detected; preserving current source unchanged.'
}

try {
    Push-Location $root
    try {
        & dotnet build '.\src\SharpEmu.Core\SharpEmu.Core.csproj' -c Debug --nologo
        if ($LASTEXITCODE -ne 0) {
            throw ('SharpEmu.Core build failed with exit code {0}.' -f $LASTEXITCODE)
        }

        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw ('SharpEmu.CLI build failed with exit code {0}.' -f $LASTEXITCODE)
        }
    }
    finally {
        Pop-Location
    }
}
catch {
    if ($changed -and $null -ne $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $backupPath -Destination $selfLoader -Force
        Write-Host '[V62.0.3] Build failed; SelfLoader.cs restored automatically.' -ForegroundColor Yellow
    }

    throw
}

Write-Host '[V62.0.3] SUCCESS'
Write-Host '[V62.0.3] Current loader baseline preserved/adapted safely.'
Write-Host '[V62.0.3] Next: RUN_AUDIT_GAME_LIBRARY_V62_0_3.cmd'
