. "$PSScriptRoot\common.ps1"
$repo=RepoRoot; $ime=ImeDialogSource; $presenter=PresenterSource
if(-not(Test-Path -LiteralPath $ime)){Write-Host "$script:Tag [ERROR] ImeDialogExports.cs missing: $ime" -ForegroundColor Red; exit 1}
if(-not(Test-Path -LiteralPath $presenter)){Write-Host "$script:Tag [ERROR] VulkanVideoPresenter.cs missing: $presenter" -ForegroundColor Red; exit 1}
$it=NL([IO.File]::ReadAllText($ime)); $pt=NL([IO.File]::ReadAllText($presenter))
$hasBaseIme=$it.Contains('SHARPEMU_V74_0_86_IME_VISIBLE_HOST_TEXT_INPUT') -or $it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY')
$hasBaseTyped=$pt.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')
$hasUiRoute=$pt.Contains('IsDemonSoulsUiBinkCompositePathV740841')
$applied=$it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY') -and $pt.Contains('SHARPEMU_V74_0_86_1_DS_UI_BINK_CHARACTER_CREATOR_COMPOSITE')
Write-Host "$script:Tag RepositoryRoot=$repo"
Write-Host "$script:Tag ImeSHA256=$(Sha $ime)"
Write-Host "$script:Tag PresenterSHA256=$(Sha $presenter)"
Write-Host "$script:Tag base_v74086_ime=$hasBaseIme"
Write-Host "$script:Tag base_v74086_typed_dcc=$hasBaseTyped"
Write-Host "$script:Tag base_ui_bink_route=$hasUiRoute"
if($applied){ Write-Host "$script:Tag State=AlreadyApplied Ready=0 Applied=1" -ForegroundColor Yellow; exit 10 }
if(-not $hasBaseIme -or -not $hasBaseTyped -or -not $hasUiRoute){
    Write-Host "$script:Tag [ERROR] Baseline mismatch. Install the V74.0.86 IME fix and keep the V74.0.84.1 UI-Bink route in source before applying this package." -ForegroundColor Red
    exit 2
}
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
