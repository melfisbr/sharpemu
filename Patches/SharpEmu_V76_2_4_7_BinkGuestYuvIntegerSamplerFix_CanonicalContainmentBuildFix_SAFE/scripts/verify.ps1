Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
$guardScript = Get-TargetGuardScript
Assert-PowerShellParses $guardScript
$state = Get-ContainmentState $guardScript
if ($state -ne 'Applied') { throw "VERIFY FAILED: canonical containment guard state=$state" }
# Verify the target package still exists and its original functional patcher is present.
$targetPatcher = Join-Path $script:TargetV1Root 'scripts\patch_target.ps1'
if (-not (Test-Path -LiteralPath $targetPatcher -PathType Leaf)) { throw "VERIFY FAILED: target patcher missing: $targetPatcher" }
Write-Tag "VERIFY PASSED. Canonical containment guard is active and V76.2.4.1 target package remains present."
