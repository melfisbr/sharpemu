. "$PSScriptRoot\common.ps1"
$p=Paths

$required=@($p.Ime,$p.ImeOverlay,$p.Sdl,$p.Presenter,$p.Host,$p.Cli)
foreach($path in $required){
    if(-not(Test-Path -LiteralPath $path)){
        Write-Host "$script:Tag [ERROR] V74.0.88.2 baseline missing file: $path" -ForegroundColor Red
        exit 1
    }
}

$ime=NL([IO.File]::ReadAllText($p.Ime))
$sdl=NL([IO.File]::ReadAllText($p.Sdl))
$presenter=NL([IO.File]::ReadAllText($p.Presenter))
$hostMovieText=NL([IO.File]::ReadAllText($p.Host))

$checks=[ordered]@{
    v88_ime_in_window=$ime.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI')
    v88_ime_overlay_file=(Test-Path -LiteralPath $p.ImeOverlay)
    v88_sdl_input=$sdl.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT')
    v88_uint_plane=$presenter.Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT')
    v88_guest_owned_loop=$hostMovieText.Contains('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP')
}

Write-Host "$script:Tag RepositoryRoot=$($p.Repo)"
Write-Host "$script:Tag HostMovieSHA256=$(Sha $p.Host)"

$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){$issues++}
}
if($issues -gt 0){
    Write-Host "$script:Tag [ERROR] V74.0.88.2 accumulated baseline is not installed. issues=$issues" -ForegroundColor Red
    exit 2
}

if($hostMovieText.Contains('SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE')){
    Write-Host "$script:Tag State=AlreadyApplied Ready=0 Applied=1" -ForegroundColor Yellow
    exit 10
}

try{
    $span=FindMethodSpan $hostMovieText '(?m)^[ \t]*private static bool TryRestartDemonSoulsUiBinkLoopV74088\(' 'TryRestartDemonSoulsUiBinkLoopV74088'
    $body=Body $hostMovieText $span
    $wide=([regex]::Matches($body,[regex]::Escape('!IsDemonSoulsUiBinkCompositePathV740841(hostPath) ||'))).Count
    Write-Host "$script:Tag loop_scope_wide_classifier_count=$wide"
    if($wide -ne 1){
        Write-Host "$script:Tag [ERROR] Expected the V74.0.88.2 broad UI-Bink loop classifier exactly once." -ForegroundColor Red
        exit 3
    }
}
catch{
    Write-Host "$script:Tag [ERROR] loop-scope structural probe failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 3
}

Write-Host "$script:Tag Finding: the post-intro freeze is consistent with the V88 EOF rewind being scoped to the entire UI-Bink classifier, which includes the title/intro loop." -ForegroundColor Cyan
Write-Host "$script:Tag Repair: only main_menu.bk2 and main_menu_ngp.bk2 will rewind; intro/title completion remains guest-visible." -ForegroundColor Cyan
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
