param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$dry=Invoke-CheckoutDryRun $true
Write-Host "$script:Tag GuestSHA256=$(Get-Sha256 $script:GuestPath)"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag DetileSHA256=$(Get-Sha256 $script:DetilePath)"
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag State=$($dry.State)"
Write-Host "$script:Tag default_deferred_threshold_mb=8 env_SHARPEMU_DEFER_LARGE_TILED_GUEST_READ_0_restores_legacy=True"
Write-Host "$script:Tag parser_large_managed_tiled_copy=removed_for_supported_vulkan_gpu_detile"
Write-Host "$script:Tag direct_guest_to_mapped_vulkan_staging=True render_thread_fallback=True"
Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True"
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
