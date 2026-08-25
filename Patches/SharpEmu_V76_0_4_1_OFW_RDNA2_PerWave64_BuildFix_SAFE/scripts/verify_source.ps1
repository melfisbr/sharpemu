$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Package
$state = Get-SourceState
if ($state -ne 'V76.0.4.1-Applied') { throw "$Tag SOURCE VERIFY FAILED state=$state" }
$txt = Get-Content -LiteralPath $Target -Raw
$required = @(
    'multiWaveActiveMask',
    'multiWaveLowMask',
    'multiWaveHighMask',
    'multiWaveHasLow',
    'multiWaveHasHigh',
    'multiWaveFirstLow',
    'multiWaveFirstHigh',
    'multiWaveFirstLane',
    'BroadcastGuestWaveLaneV7604(value, multiWaveFirstLane)'
)
foreach ($marker in $required) {
    if (-not $txt.Contains($marker)) { throw "$Tag SOURCE VERIFY missing marker: $marker" }
}
Write-Host "$Tag SOURCE VERIFY PASSED. sha=$ExpectedFixedSha" -ForegroundColor Green
