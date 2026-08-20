. "$PSScriptRoot\common.ps1"
$p=Paths
try{Assert-V74088 $p.Repo}catch{
    Write-Host "$script:Tag [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$ime=NL([IO.File]::ReadAllText($p.Ime))
$overlay=NL([IO.File]::ReadAllText($p.ImeOverlay))
$sdl=NL([IO.File]::ReadAllText($p.Sdl))
$presenter=NL([IO.File]::ReadAllText($p.Presenter))
$host=NL([IO.File]::ReadAllText($p.Host))

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "ime_in_window_system_ui=$($ime.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI'))"
Write-Host "ime_external_process_removed=$(-not $ime.Contains('ProcessStartInfo') -and -not $ime.Contains('powershell.exe'))"
Write-Host "ime_overlay_renderer=$($overlay.Contains('backend=sdl-vulkan-overlay'))"
Write-Host "ime_gamepad_input=$($sdl.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_GAMEPAD_INPUT'))"
Write-Host "ime_keyboard_input=$($sdl.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT'))"
Write-Host "ui_bink_uint_contract=$($presenter.Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT'))"
Write-Host "ui_bink_single_plane_bootstrap=$($presenter.Contains('FindTypedUiBinkPlaneBindingsV74088'))"
Write-Host "ui_bink_r8uint=$($presenter.Contains('desiredLumaFormatV74088'))"
Write-Host "ui_bink_r8g8uint=$($presenter.Contains('desiredChromaFormatV74088'))"
Write-Host "ui_bink_guest_owned_loop=$($host.Contains('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP'))"
Write-Host "v8421_frame_ownership_preserved=$($presenter.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP'))"
Write-Host "v8421_sticky_plane_preserved=$($presenter.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY'))"
Write-Host "v86_typed_dcc_preserved=$($presenter.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC'))"
Write-Host "build_artifact_exists=$(Test-Path -LiteralPath $p.Exe)"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
