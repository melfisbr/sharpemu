param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $packageRoot

$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$decoder = Join-Path $root 'src\SharpEmu.Core\Loader\Ps5SceDynamicImportMetadata.cs'

if (-not (Test-Path -LiteralPath $selfLoader -PathType Leaf)) {
    throw ('[V73.1] PRECHECK ERROR: missing {0}' -f $selfLoader)
}

$source = [IO.File]::ReadAllText($selfLoader)

$anchors = @(
    'private const long DtSceNeededModule = 0x6100000F;',
    'private const long DtSceImportLib = 0x61000015;',
    'CollectNeededModuleNames(',
    'ParseSceImportMetadata(',
    'TryDecodeSceMetadataName(',
    'libraries[EncodeSceId(id)]',
    'case DtSceNeededModule:'
)
foreach ($anchor in $anchors) {
    if (-not (Test-ContainsOrdinal -Text $source -Pattern $anchor)) {
        throw ('[V73.1] PRECHECK ERROR: current SelfLoader anchor missing: {0}' -f $anchor)
    }
}

$hasLibrarySwitchAnchor =
    (Test-ContainsOrdinal -Text $source -Pattern 'case DtSceImportLib:') -or
    (Test-ContainsOrdinal -Text $source -Pattern 'tag == DtSceImportLib')
if (-not $hasLibrarySwitchAnchor) {
    throw '[V73.1] PRECHECK ERROR: current SCE library metadata branch was not recognized.'
}

$hasNeededConstant = Test-ContainsOrdinal -Text $source -Pattern 'DtSceNeededModuleGen5 = 0x61000045'
$hasLibraryConstant = Test-ContainsOrdinal -Text $source -Pattern 'DtSceImportLibGen5 = 0x61000049'
$hasNeededCollection = Test-ContainsOrdinal -Text $source -Pattern 'DtSceNeededModule || tag == DtSceNeededModuleGen5'
$hasModuleCase = Test-ContainsOrdinal -Text $source -Pattern 'case DtSceNeededModuleGen5:'
$hasLibraryCase = Test-ContainsOrdinal -Text $source -Pattern 'case DtSceImportLibGen5:'

$state = if ($hasNeededConstant -and $hasLibraryConstant -and $hasNeededCollection -and $hasModuleCase -and $hasLibraryCase) {
    'already-integrated'
}
elseif ($hasNeededConstant -or $hasLibraryConstant -or $hasNeededCollection -or $hasModuleCase -or $hasLibraryCase) {
    'partially-integrated'
}
else {
    'baseline-needs-gen5-tags'
}

Write-Host '[V73.1] PRECHECK PASSED.'
Write-Host ('[V73.1] SelfLoader_SHA256={0}' -f (Get-FileHash -LiteralPath $selfLoader -Algorithm SHA256).Hash)
Write-Host ('[V73.1] gen5_metadata_state={0}' -f $state)
Write-Host ('[V73.1] decoder_present={0}' -f (Test-Path -LiteralPath $decoder -PathType Leaf))
Write-Host '[V73.1] No NID fallback, relocation, GPU or imported-data semantics will be replaced.'
