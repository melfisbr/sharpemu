param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$already=$s.Presenter.Contains('SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
$fairOptIn=$s.Fairness.Text.Contains('string.Equals') -and -not $s.Fairness.Text.Contains('!string.Equals') -and $s.Fairness.Text.Contains('"1"')
$fairDefault=$s.Fairness.Text.Contains('!string.Equals') -and $s.Fairness.Text.Contains('"0"')
$adaptOptIn=$s.Adaptive.Text.Contains('string.Equals') -and -not $s.Adaptive.Text.Contains('!string.Equals') -and $s.Adaptive.Text.Contains('"1"')
$adaptDefault=$s.Adaptive.Text.Contains('!string.Equals') -and $s.Adaptive.Text.Contains('"0"')
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag v84_already=$already"
Write-Host "$script:Tag submission_fairness_optin=$fairOptIn default_on=$fairDefault"
Write-Host "$script:Tag adaptive_unified_optin=$adaptOptIn default_on=$adaptDefault"
Write-Host "$script:Tag soft_target_default_8=$($s.Presenter.Contains('SHARPEMU_VK_MAX_INFLIGHT_SUBMISSIONS') -and $s.Presenter.Contains('8'))"
Write-Host "$script:Tag emergency_headroom_existing_24=$($s.Presenter.Contains('SHARPEMU_KYTY_EMERGENCY_INFLIGHT_SUBMISSIONS') -and $s.Presenter.Contains('24'))"
Write-Host "$script:Tag adaptive_max_groups_existing_65536=$($s.Presenter.Contains('SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE_MAX_GROUPS') -and $s.Presenter.Contains('65536'))"
Write-Host "$script:Tag indirect_dispatch_excluded=$($s.Presenter.Contains('work.IsIndirect'))"
Write-Host "$script:Tag v81_2_boundaries_preserved=$($s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))"
Write-Host "$script:Tag v82_nonblocking_preserved=$($s.Presenter.Contains('SHARPEMU_V74_0_82_NONBLOCKING_ORDERED_VISIBILITY_DEFAULT'))"
Write-Host "$script:Tag rigid_sha_gate=False preserves_accumulated_source=True"
if(-not $already){if(-not($fairOptIn -or $fairDefault)){throw "$script:Tag fairness declaration possui semantica desconhecida."};if(-not($adaptOptIn -or $adaptDefault)){throw "$script:Tag adaptive declaration possui semantica desconhecida."}}
if($already){Write-Host "$script:Tag State=AlreadyApplied"}else{Write-Host "$script:Tag State=Ready"}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
