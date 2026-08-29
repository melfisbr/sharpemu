param()
. (Join-Path $PSScriptRoot 'common.ps1')

Ensure-Layout
Assert-SemanticDualQueueContract | Out-Null

$beforeHash = Get-HashLower $PresenterPath
$already = ([IO.File]::ReadAllText($PresenterPath)).Contains($CompatMarker)

Write-Host "[$Tag] presenter_sha_before=$beforeHash"
Write-Host "[$Tag] compatibility_marker_present=$already"

Write-Host (
    "[$Tag] PRECHECK PASSED " +
    "reason=V21.0-validator-expects-CLI-contract-name-in-Presenter " +
    "actual-dual-queue-semantics=verified"
)


$presenterNow = [IO.File]::ReadAllText($PresenterPath)
$legacyCountSite = $presenterNow.Contains(
    'CommandBufferCount = MaxFramesInFlight,')
$fixedCountSite = $presenterNow.Contains(
    'CommandBufferCount = (uint)MaxFramesInFlight,')

if (-not $legacyCountSite -and -not $fixedCountSite) {
    Fail 'CommandBufferCount MaxFramesInFlight compile site ausente'
}

Write-Host (
    "[$Tag] UINT PRECHECK PASSED " +
    "legacy_site=$legacyCountSite fixed_site=$fixedCountSite"
)
