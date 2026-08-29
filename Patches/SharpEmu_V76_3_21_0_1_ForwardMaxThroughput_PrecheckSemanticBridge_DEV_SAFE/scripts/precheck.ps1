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
