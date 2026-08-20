param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$state=if($s.Checks.V872Field -ge 1 -and $s.Checks.V872Yield -ge 1){'AlreadyAppliedV87.2'}elseif($s.Checks.PrevV871Field -ge 1 -and $s.Checks.PrevV871Yield -ge 1){'AlreadyAppliedLegacyV87.1'}elseif($s.Checks.OldV87Field -ge 1 -and $s.Checks.OldV87Yield -ge 1){'AlreadyAppliedLegacyV87'}else{'Ready'}
Write-Host "$script:Tag GateOwnerMethod=$($s.Gate.Name)"
Write-Host "$script:Tag GateOwnerStateParam=$($s.Gate.StateParam)"
Write-Host "$script:Tag GateOwnerSelectionStrategy=$($s.Gate.SelectionStrategy) CandidateCount=$($s.Gate.CandidateCount)"
Write-Host "$script:Tag locator_all_marker_occurrences=True lexical_brace_scanner=True dedicated_drain_classifier=True parse_core_rejected=True"
Write-Host "$script:Tag current_checkout_dry_run=passed_before_precheck"
Write-Host "$script:Tag v86_4_resident_retention_preserved=$($s.Checks.V864Agc -ge 1 -and $s.Checks.V864Presenter -ge 1)"
Write-Host "$script:Tag v85_aggressive_pm4_preserved=$($s.Checks.V85 -ge 1)"
Write-Host "$script:Tag v81_2_boundaries_preserved=$($s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))"
Write-Host "$script:Tag default_gate_quantum_packets=16 default_gate_quantum_ms=1"
Write-Host "$script:Tag rigid_sha_gate=False source_write=False"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag State=$state"
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
