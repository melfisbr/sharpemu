param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot

$self=Join-Path $r 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$ph=Join-Path $r 'src\SharpEmu.Core\Loader\ProgramHeader.cs'
$eh=Join-Path $r 'src\SharpEmu.Core\Loader\ElfHeader.cs'
foreach($p in @($self,$ph,$eh)) {
    if (!(Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "PRECHECK ERROR: missing $p"
    }
}

$s=[IO.File]::ReadAllText($self)
foreach($anchor in @(
    'private static LoadContext ParseLayout(ReadOnlySpan<byte> imageData)',
    'private static IReadOnlyDictionary<ulong, string> ResolveAndPatchImportStubs(',
    'AppendSectionRelocationDescriptors('
)) {
    if (!(Test-ContainsOrdinal $s $anchor)) {
        throw "PRECHECK ERROR: current loader structural anchor missing: $anchor"
    }
}

$phState='unknown'
if (Test-ContainsOrdinal $s 'header.ProgramHeaderEntrySize != ProgramHeaderSize') {
    $phState='strict-equality-old'
} elseif (
    (Test-ContainsOrdinal $s 'header.ProgramHeaderEntrySize < ProgramHeaderSize') -or
    (Test-ContainsOrdinal $s 'ProgramHeaderEntrySize < ProgramHeaderSize')
) {
    $phState='minimum-size-compatible'
} elseif (Test-ContainsOrdinal $s 'ProgramHeaderEntrySize') {
    $phState='custom-validation'
} else {
    $phState='no-explicit-check'
}

Write-Host '[V62.0.1] PRECHECK PASSED.'
Write-Host "[V62.0.1] program_header_validation=$phState"
Write-Host '[V62.0.1] Exact-equality V62.0 prerequisite is no longer required.'
