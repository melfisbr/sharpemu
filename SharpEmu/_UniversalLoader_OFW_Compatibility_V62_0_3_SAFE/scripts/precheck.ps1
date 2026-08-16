param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepositoryRoot -RepositoryRoot $RepositoryRoot
$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$programHeader = Join-Path $root 'src\SharpEmu.Core\Loader\ProgramHeader.cs'
$elfHeader = Join-Path $root 'src\SharpEmu.Core\Loader\ElfHeader.cs'

$requiredFiles = @($selfLoader, $programHeader, $elfHeader)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw ('PRECHECK ERROR: missing {0}' -f $requiredFile)
    }
}

$source = [IO.File]::ReadAllText($selfLoader)
$requiredAnchors = @(
    'private static LoadContext ParseLayout(ReadOnlySpan<byte> imageData)',
    'private static IReadOnlyDictionary<ulong, string> ResolveAndPatchImportStubs(',
    'AppendSectionRelocationDescriptors('
)

foreach ($anchor in $requiredAnchors) {
    if (-not (Test-TextContains -Text $source -Pattern $anchor)) {
        throw ('PRECHECK ERROR: current loader structural anchor missing: {0}' -f $anchor)
    }
}

$programHeaderValidation = 'unknown'
if (Test-TextContains -Text $source -Pattern 'header.ProgramHeaderEntrySize != ProgramHeaderSize') {
    $programHeaderValidation = 'strict-equality-old'
}
elseif (
    (Test-TextContains -Text $source -Pattern 'header.ProgramHeaderEntrySize < ProgramHeaderSize') -or
    (Test-TextContains -Text $source -Pattern 'ProgramHeaderEntrySize < ProgramHeaderSize')
) {
    $programHeaderValidation = 'minimum-size-compatible'
}
elseif (Test-TextContains -Text $source -Pattern 'ProgramHeaderEntrySize') {
    $programHeaderValidation = 'custom-validation'
}
else {
    $programHeaderValidation = 'no-explicit-check'
}

Write-Host '[V62.0.3] PRECHECK PASSED.'
Write-Host ('[V62.0.3] program_header_validation={0}' -f $programHeaderValidation)
Write-Host '[V62.0.3] No obsolete exact-equality baseline is required.'
