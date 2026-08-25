param()
. (Join-Path $PSScriptRoot 'common.ps1')

& (Join-Path $PSScriptRoot 'validate_package.ps1')
$media=Assert-CurrentMediaStructure
Assert-PerfMarkers

$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$temp=
    Join-Path ([IO.Path]::GetTempPath()) (
        'SharpEmu_V11876313_HostMovieBridge_' +
        [Guid]::NewGuid().ToString('N') +
        '.cs')

try {
    $preview=Invoke-HybridTransform $media.Path $temp
    Write-Tag (
        "preflight_HostMovieBridge status=$($preview.Status) " +
        "sha_before=$($preview.Before) sha_after=$($preview.After) source_write=0")

    Invoke-SyntaxProbe $temp 'HostMovieBridgeHybridRestore'

    $previewText=[IO.File]::ReadAllText($temp)
    foreach($marker in @(
        'SHARPEMU_V74_0_118_7_6_3_13_RAD_NIHAV_HYBRID_RESTORE',
        '[V74.0.84.1][UI_BINK_INTERNAL]',
        '[V74.0.118.7.6.3.13][RAD_NIHAV_HYBRID_ROUTE]')) {
        if(-not$previewText.Contains($marker)) {
            throw "$script:Tag transformed HostMovieBridge postcondition missing: $marker"
        }
    }

    $perf=Get-PerfSnapshot
    $report=
        Join-Path $patches (
            "SharpEmu_V74_0_118_7_6_3_13_PRECHECK_$stamp.txt")
    @(
        "version=$script:Version",
        "host_movie_bridge_before=$($preview.Before)",
        "host_movie_bridge_after_preview=$($preview.After)",
        "host_movie_bridge_state=$($media.State)",
        "historical_media_baseline=V74.0.88.6.2",
        "fullscreen_backend=official-rad",
        "ui_backend=nihav",
        "ui_files=logo_intro_loop.bk2;main_menu.bk2;main_menu_ngp.bk2",
        "ui_rad_interactive_default=disabled",
        "ui_rad_interactive_diagnostic_optin=SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE=1",
        "performance_sources_touched=0",
        "perf_native_worker_sha=$($perf.NativeWorker)",
        "perf_presenter_sha=$($perf.Presenter)",
        "perf_agc_sha=$($perf.Agc)",
        "perf_nihav_sha=$($perf.Nihav)",
        "perf_playback_sha=$($perf.Playback)"
    ) | Set-Content -LiteralPath $report -Encoding UTF8

    Write-Tag "PRECHECK=$report"
    Write-Tag 'PRECHECK PASSED. Nothing changed.'
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
