. "$PSScriptRoot\common.ps1"
$p=Paths
try{
    Assert-V740883 $p.Repo
}
catch{
    Write-Host "$script:Tag [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$hostMovieText=NL([IO.File]::ReadAllText($p.Host))
$span=FindMethodSpan $hostMovieText '(?m)^[ \t]*private static bool TryRestartDemonSoulsUiBinkLoopV74088\(' 'TryRestartDemonSoulsUiBinkLoopV74088'
$body=Body $hostMovieText $span

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "v88_inwindow_ime_preserved=$(Test-Path -LiteralPath $p.ImeOverlay)"
Write-Host "v88_uint_plane_preserved=$([IO.File]::ReadAllText($p.Presenter).Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT'))"
Write-Host "main_menu_only_loop_scope=$($body.Contains('SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE'))"
Write-Host "main_menu_loop_allowed=$($body.Contains('""main_menu.bk2""'))"
Write-Host "main_menu_ngp_loop_allowed=$($body.Contains('""main_menu_ngp.bk2""'))"
Write-Host "wide_classifier_removed=$(-not $body.Contains('!IsDemonSoulsUiBinkCompositePathV740841(hostPath)'))"
Write-Host "logo_intro_not_explicitly_looped=$(-not $body.Contains('""logo_intro_loop.bk2""'))"
Write-Host "live_log_runner=$([IO.File]::ReadAllText((Join-Path (PackageRoot) 'scripts\run_test.ps1')).Contains('LIVE_RUNTIME_LOG'))"
Write-Host "build_artifact_exists=$(Test-Path -LiteralPath $p.Exe)"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
