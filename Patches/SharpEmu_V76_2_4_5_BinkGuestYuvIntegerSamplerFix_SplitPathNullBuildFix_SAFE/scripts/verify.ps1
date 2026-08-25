. (Join-Path $PSScriptRoot 'common.ps1')

$state = Get-TargetStateV76245
if ($state -ne 'Applied') { throw "$PackageTag target script is not Applied: $state" }
Assert-PowerShellParsesV76245 $TargetScript
$targetText = Read-TextV76245 $TargetScript
$remaining = Get-SuspiciousSplitPathCountV76245 $targetText
if ($remaining -ne 0) { throw "$PackageTag suspicious Split-Path null remains: $remaining" }
if (-not $targetText.Contains('[System.IO.Directory]::GetParent($PSScriptRoot).FullName')) {
    throw "$PackageTag deterministic Patches path initializer missing"
}
Write-Host "$PackageTag SOURCE/PACKAGE VERIFY PASSED. Target=$TargetRoot"
