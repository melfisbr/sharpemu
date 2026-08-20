param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$pm4On=$s.Pm4.Text.Contains('!string.Equals') -and $s.Pm4.Text.Contains('"0"')
$inlineOn=$s.Inline.Text.Contains('!string.Equals') -and $s.Inline.Text.Contains('"0"')
$v85=$s.Agc.Contains('SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')
Write-Host "$script:Tag pm4_scheduler_default_on=$pm4On"
Write-Host "$script:Tag inline_write_data_default_on=$inlineOn"
Write-Host "$script:Tag release_queue_only_present=$($s.Agc.Contains('_releaseMemQueueCompletionOnlyV74085'))"
Write-Host "$script:Tag local_payload_dedup_present=$($s.Agc.Contains('_localTexturePayloadDedupV74085'))"
Write-Host "$script:Tag v81_2_boundaries_preserved=$($s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag State=$(if($v85){'AlreadyApplied'}else{'Ready'})"
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
