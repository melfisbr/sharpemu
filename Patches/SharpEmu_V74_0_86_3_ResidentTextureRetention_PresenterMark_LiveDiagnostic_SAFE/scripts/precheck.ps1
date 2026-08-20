param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$v863=$s.Agc.Contains('SHARPEMU_V74_0_86_3_RESIDENT_TEXTURE_RETENTION_PRESENTER_MARK') -and $s.Presenter.Contains('SHARPEMU_V74_0_86_3_RESIDENT_TEXTURE_RETENTION_PRESENTER_MARK')
Write-Host "$script:Tag standalone_texture_cache_default_3072=$($s.Budget.Text -match 'SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB[\s\S]*?3072')"
Write-Host "$script:Tag large_snapshot_ttl_default_10000=$($s.Ttl.Text -match ':\s*10000L\s*;')"
Write-Host "$script:Tag resident_cpu_bridge_release_present=$($s.Agc.Contains('ReleaseResidentCpuBridgeSnapshotsV740863'))"
Write-Host "$script:Tag presenter_mark_release_call_present=$($s.Presenter.Contains('ReleaseResidentCpuBridgeSnapshotsV740863(identity.Address)'))"
Write-Host "$script:Tag presenter_mark_contract=True"
Write-Host "$script:Tag texture_factory_anchor_required=False"
Write-Host "$script:Tag sampled_address_anchor_required=False"
Write-Host "$script:Tag v85_aggressive_pm4_preserved=$($s.Agc.Contains('SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE'))"
Write-Host "$script:Tag v81_2_boundaries_preserved=$($s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag State=$(if($v863){'AlreadyApplied'}else{'Ready'})"
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
