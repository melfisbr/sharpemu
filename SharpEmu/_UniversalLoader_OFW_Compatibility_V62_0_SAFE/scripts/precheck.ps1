param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
$self=Join-Path $r 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$ph=Join-Path $r 'src\SharpEmu.Core\Loader\ProgramHeader.cs'
foreach($p in @($self,$ph)){if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "PRECHECK ERROR: missing $p"}}
$s=[IO.File]::ReadAllText($self)
$anchors=@(
 'private static LoadContext ParseLayout(ReadOnlySpan<byte> imageData)',
 'if (header.ProgramHeaderEntrySize != ProgramHeaderSize)',
 'if (!TryGetProgramHeader(programHeaders, ProgramHeaderType.Dynamic, out var dynamicHeader, out var dynamicHeaderIndex))',
 'private static int AppendSectionRelocationDescriptors('
)
foreach($a in $anchors){if($s.IndexOf($a,[StringComparison]::Ordinal)-lt 0){throw "PRECHECK ERROR: loader baseline anchor missing: $a"}}
Write-Host '[V62.0] PRECHECK PASSED.'
Write-Host '[V62.0] Loader baseline supports OFW-aligned compatibility transform.'
