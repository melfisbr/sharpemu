param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$already=$p.Contains('SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
$orderedDefaultOn=$p.Contains('SHARPEMU_V74_0_82_NONBLOCKING_ORDERED_VISIBILITY_DEFAULT')
$dccIndex=$p.Contains('SHARPEMU_V74_0_82_DCC_METADATA_INDEX')
$optin=$false
$start=$p.IndexOf('private static readonly bool _nonBlockingOrderedVisibilityV740293 =',[System.StringComparison]::Ordinal)
if($start -ge 0){$semi=$p.IndexOf(';',$start,[System.StringComparison]::Ordinal);if($semi -gt $start){$seg=$p.Substring($start,$semi-$start+1);$optin=($seg.Contains('"1"') -and -not $seg.Contains('!string.Equals'))}}
$m=[regex]::Match($p,'(?m)^\s*private\s+bool\s+TryResolveGuestImageMetadataAliasV7405632\s*\(')
if(-not $m.Success){throw "$script:Tag DCC resolver signature missing."}
$tail=$p.Substring($m.Index+$m.Length)
$next=[regex]::Match($tail,'(?m)^\s*private\s+static\s+bool\s+IsUsableGuestImageAlias\s*\(')
if(-not $next.Success){throw "$script:Tag DCC resolver end anchor missing."}
$dseg=$p.Substring($m.Index,$m.Length+$next.Index)
$activeLoops=([regex]::Matches($dseg,'foreach\s*\(\s*var\s+candidate\s+in\s+_guestImages\.Values\s*\)')).Count
$variantLoops=([regex]::Matches($dseg,'foreach\s*\(\s*var\s+candidate\s+in\s+_guestImageVariants\.Values\s*\)')).Count
$metadataAssignments=([regex]::Matches($p,'(?ms)if\s*\(\s*target\.MetadataAddress\s*!=\s*0\s*\)\s*\{\s*(existing|retained)\.MetadataAddress\s*=\s*target\.MetadataAddress\s*;\s*\}')).Count
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag v82_already=$already"
Write-Host "$script:Tag ordered_visibility_default_on=$orderedDefaultOn legacy_optin_form=$optin"
Write-Host "$script:Tag dcc_metadata_index=$dccIndex"
Write-Host "$script:Tag dcc_active_global_loops=$activeLoops dcc_variant_global_loops=$variantLoops metadata_assignment_blocks=$metadataAssignments"
Write-Host "$script:Tag dcc_v80_preserved=$($p.Contains('DCC_PROVENANCE_RECOVERY'))"
Write-Host "$script:Tag v81_2_boundaries_preserved=$($p.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $p.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))"
Write-Host "$script:Tag rigid_sha_gate=False"
if(-not $already -and ($activeLoops -ne 1 -or $variantLoops -ne 1)){throw "$script:Tag expected one DCC global loop per dictionary before V82; found active=$activeLoops variants=$variantLoops."}
if(-not $already -and $metadataAssignments -lt 2){throw "$script:Tag expected existing/retained MetadataAddress assignment blocks; found $metadataAssignments."}
if($already){Write-Host "$script:Tag State=AlreadyApplied"}else{Write-Host "$script:Tag State=Ready"}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
