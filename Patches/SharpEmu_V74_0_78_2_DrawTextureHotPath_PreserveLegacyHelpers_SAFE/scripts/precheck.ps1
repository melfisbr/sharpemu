param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$state=Assert-StructuralContracts
$p=$state.Presenter
$a=$state.Agc

$markerPresenter=$p.Contains('SHARPEMU_V74_0_78_2_PRESERVE_LEGACY_TEXTURE_CACHE_WRAPPER')
$uninit=($a -match 'AllocateUninitializedArray<byte>\s*\(\s*checked\(\(int\)physicalSourceByteCount\)\s*\)')
$normalizeDefs=([regex]::Matches($p,'(?m)^[ \t]*(?:private|internal)\s+static\s+[^\r\n]*\bNormalizeSamplerIdentityV74075\s*\(')).Count
$normalizeRefs=([regex]::Matches($p,'\bNormalizeSamplerIdentityV74075\s*\(')).Count
$ignoringDefs=([regex]::Matches($p,'(?m)^[ \t]*(?:private|internal)\s+static\s+bool\s+IsTextureContentCachedIgnoringSamplerV74074\s*\(')).Count
$ignoringAgcRefs=([regex]::Matches($a,'\bIsTextureContentCachedIgnoringSamplerV74074\s*\(')).Count

Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag preserve_legacy_wrapper=$markerPresenter"
Write-Host "$script:Tag uninitialized_large_snapshot=$uninit"
Write-Host "$script:Tag NormalizeSamplerIdentityV74075_defs=$normalizeDefs refs=$normalizeRefs"
Write-Host "$script:Tag IsTextureContentCachedIgnoringSamplerV74074_defs=$ignoringDefs agc_refs=$ignoringAgcRefs"
Write-Host "$script:Tag broad_method_region_replacement=False"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag preserves_accumulated_source=True"

if($normalizeRefs -gt 0 -and $normalizeDefs -eq 0){throw "$script:Tag baseline already has unresolved NormalizeSamplerIdentityV74075 references; refusing to layer patch."}
if($ignoringAgcRefs -gt 0 -and $ignoringDefs -eq 0){throw "$script:Tag baseline already has unresolved IsTextureContentCachedIgnoringSamplerV74074 reference; refusing to layer patch."}
if($markerPresenter -and $uninit){Write-Host "$script:Tag State=AlreadyApplied"}else{Write-Host "$script:Tag State=Ready"}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
