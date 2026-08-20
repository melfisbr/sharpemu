param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
Write-Host "$script:Tag GateOwnerMethod=$($s.Gate.Name)"
Write-Host "$script:Tag GateOwnerStateParam=$($s.Gate.StateParam)"
Write-Host "$script:Tag gate_quantum_marker_present=$($s.Agc.Contains('SHARPEMU_V74_0_87_COOPERATIVE_GATE_QUANTUM'))"
Write-Host "$script:Tag v86_4_resident_retention_preserved=$($s.Checks.V864Agc -ge 1 -and $s.Checks.V864Presenter -ge 1)"
Write-Host "$script:Tag v85_aggressive_pm4_preserved=$($s.Checks.V85 -ge 1)"
Write-Host "$script:Tag v81_2_boundaries_preserved=$($s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))"
Write-Host "$script:Tag default_gate_quantum_packets=16 default_gate_quantum_ms=1"
Write-Host "$script:Tag packet_atomicity=preserved yield_site=after_V72_gate_owner_drain"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag State=$(if($s.Checks.V87 -ge 1){'AlreadyApplied'}else{'Ready'})"
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
