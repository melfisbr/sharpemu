param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r

$self=Join-Path $r 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$s=[IO.File]::ReadAllText($self)
$changed=$false
$backup=$null

# Apply only the PH-size widening when the *old exact form* is genuinely present.
# If the user's loader is already minimum-size compatible, leave it untouched.
$old=@'
        if (header.ProgramHeaderEntrySize != ProgramHeaderSize)
        {
            throw new InvalidDataException($"Unsupported ELF program header entry size: {header.ProgramHeaderEntrySize}.");
        }
'@
$new=@'
        // V62.0.1 OFW_LOADER_COMPAT
        // ELF64 permits a larger program-header record when the standard
        // leading fields remain present. The parser consumes the known prefix
        // using the advertised e_phentsize stride.
        if (header.ProgramHeaderEntrySize < ProgramHeaderSize)
        {
            throw new InvalidDataException(
                $"ELF program header entry size {header.ProgramHeaderEntrySize} is smaller than the required {ProgramHeaderSize}-byte ELF64 prefix.");
        }
'@

if ($s.IndexOf($old,[StringComparison]::Ordinal) -ge 0) {
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir=Join-Path $r ".sharpemu-hotfix-backup\UniversalLoader_V62_0_1_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backup=Join-Path $backupDir 'SelfLoader.cs'
    Copy-Item -LiteralPath $self -Destination $backup
    $s=$s.Replace($old,$new)
    [IO.File]::WriteAllText($self,$s,[Text.UTF8Encoding]::new($false))
    $changed=$true
    Write-Host "[V62.0.1] Strict e_phentsize equality widened. Backup: $backupDir"
}
elseif (
    (Test-ContainsOrdinal $s 'header.ProgramHeaderEntrySize < ProgramHeaderSize') -or
    (Test-ContainsOrdinal $s 'ProgramHeaderEntrySize < ProgramHeaderSize')
) {
    Write-Host '[V62.0.1] e_phentsize is already minimum-size compatible; no duplicate edit.'
}
else {
    Write-Host '[V62.0.1] Custom PH validation detected; preserving current source unchanged.'
}

try {
    Push-Location $r
    try {
        & dotnet build '.\src\SharpEmu.Core\SharpEmu.Core.csproj' -c Debug --nologo
        if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Core build failed: $LASTEXITCODE" }

        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed: $LASTEXITCODE" }
    }
    finally { Pop-Location }
}
catch {
    if ($changed -and $null -ne $backup -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $self -Force
        Write-Host '[V62.0.1] Build failed; SelfLoader.cs restored automatically.' -ForegroundColor Yellow
    }
    throw
}

Write-Host '[V62.0.1] SUCCESS'
Write-Host '[V62.0.1] Current loader baseline preserved/adapted safely.'
Write-Host '[V62.0.1] Next: RUN_AUDIT_GAME_LIBRARY_V62_0_1.cmd'
