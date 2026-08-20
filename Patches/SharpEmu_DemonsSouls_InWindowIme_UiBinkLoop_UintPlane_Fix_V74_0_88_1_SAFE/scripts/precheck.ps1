. "$PSScriptRoot\common.ps1"
$p=Paths
$required=@($p.Ime,$p.Sdl,$p.Presenter,$p.Host,$p.Cli)
foreach($path in $required){
    if(-not(Test-Path -LiteralPath $path)){
        Write-Host "$script:Tag [ERROR] Missing required source: $path" -ForegroundColor Red
        exit 1
    }
}

$ime=NL([IO.File]::ReadAllText($p.Ime))
$sdl=NL([IO.File]::ReadAllText($p.Sdl))
$presenter=NL([IO.File]::ReadAllText($p.Presenter))
$hostMovieText=NL([IO.File]::ReadAllText($p.Host))

$already=
    $ime.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI') -and
    $sdl.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT') -and
    $presenter.Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT') -and
    $hostMovieText.Contains('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP')

Write-Host "$script:Tag RepositoryRoot=$($p.Repo)"
Write-Host "$script:Tag ImeSHA256=$(Sha $p.Ime)"
Write-Host "$script:Tag SdlSHA256=$(Sha $p.Sdl)"
Write-Host "$script:Tag PresenterSHA256=$(Sha $p.Presenter)"
Write-Host "$script:Tag HostMovieSHA256=$(Sha $p.Host)"

if($already){
    Write-Host "$script:Tag State=AlreadyApplied Ready=0 Applied=1" -ForegroundColor Yellow
    exit 10
}

$checks=[ordered]@{
    ime_dialog_exports=$ime.Contains('sceImeDialogInit')
    old_or_v86_ime=$ime.Contains('SHARPEMU_V74_0_86') -or $ime.Contains('SHARPEMU_V74_0_85')
    sdl_handle_key=$sdl.Contains('private void HandleKey(SDL_KeyboardEvent keyEvent)')
    sdl_sample_gamepad=$sdl.Contains('private void SampleGamepad()')
    presenter_v8421_frame=$presenter.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP')
    presenter_v8421_sticky=$presenter.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY')
    presenter_v86_typed_dcc=$presenter.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')
    presenter_overlay=$presenter.Contains('private void CreateOverlayResources()') -and $presenter.Contains('private void RecordOverlayBlit(uint imageIndex, int frameSlot)')
    host_v841_classifier=$hostMovieText.Contains('IsDemonSoulsUiBinkCompositePathV740841')
    host_decode=$hostMovieText.Contains('internal static bool TryDecodeNextFrame(')
}
$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){$issues++}
}
if($issues -gt 0){
    Write-Host "$script:Tag PRECHECK FAILED issues=$issues" -ForegroundColor Red
    exit 2
}

Write-Host "$script:Tag EBOOT finding: Character Creator game state is guest-owned; IME visual is a system-service responsibility." -ForegroundColor Cyan
Write-Host "$script:Tag Renderer finding: UI-Bink runtime showed f1/n4 + f3/n4 while legacy host candidate required NumberType=0." -ForegroundColor Cyan
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
