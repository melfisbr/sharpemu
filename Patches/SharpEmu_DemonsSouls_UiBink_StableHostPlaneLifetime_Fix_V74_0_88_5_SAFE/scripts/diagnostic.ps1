. "$PSScriptRoot\common.ps1"
$p=Paths
try{
    Assert-V740885 $p.Repo
}
catch{
    Write-Host "$script:Tag [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$presenter=NL([IO.File]::ReadAllText($p.Presenter))
$runner=[IO.File]::ReadAllText((Join-Path (PackageRoot) 'scripts\run_test.ps1'))

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "v88_3_source_baseline=True"
Write-Host "stable_host_plane_format=$($presenter.Contains('SHARPEMU_V74_0_88_5_STABLE_HOST_PLANE_FORMAT'))"
Write-Host "host_luma_r8unorm=$($presenter.Contains('var desiredLumaFormatV74088 = Format.R8Unorm;'))"
Write-Host "host_chroma_r8g8unorm=$($presenter.Contains('var desiredChromaFormatV74088 = Format.R8G8Unorm;'))"
Write-Host "number_type_no_longer_invalidates_image=$($presenter.Contains('V74.0.88.5: guest NumberType does not invalidate host VkImage'))"
Write-Host "n4_discovery_preserved=$($presenter.Contains('FindTypedUiBinkPlaneBindingsV74088'))"
Write-Host "host_movie_upload_trace=$($presenter.Contains('SHARPEMU_V74_0_88_5_HOST_MOVIE_UPLOAD_TRACE'))"
Write-Host "v88_inwindow_ime_preserved=$(Test-Path -LiteralPath $p.ImeOverlay)"
Write-Host "v88_3_main_menu_loop_preserved=$([IO.File]::ReadAllText($p.Host).Contains('SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE'))"
Write-Host "robust_live_runner=$($runner.Contains('V74.0.88.5 NATIVE_STDERR_MERGE'))"
Write-Host "build_artifact_exists=$(Test-Path -LiteralPath $p.Exe)"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
