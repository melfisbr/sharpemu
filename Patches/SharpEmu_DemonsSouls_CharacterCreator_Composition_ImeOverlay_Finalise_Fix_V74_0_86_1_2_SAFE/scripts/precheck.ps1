. "$PSScriptRoot\common.ps1"

$repo=RepoRoot
$ime=ImeDialogSource
$presenter=PresenterSource

if(-not(Test-Path -LiteralPath $ime)){
    Write-Host "$script:Tag [ERROR] ImeDialogExports.cs missing: $ime" -ForegroundColor Red
    exit 1
}
if(-not(Test-Path -LiteralPath $presenter)){
    Write-Host "$script:Tag [ERROR] VulkanVideoPresenter.cs missing: $presenter" -ForegroundColor Red
    exit 1
}

$it=NL([IO.File]::ReadAllText($ime))
$pt=NL([IO.File]::ReadAllText($presenter))

$baseIme=$it.Contains('SHARPEMU_V74_0_86_IME_VISIBLE_HOST_TEXT_INPUT') -or $it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY')
$typed=$pt.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')
$frame=$pt.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP')
$sticky=$pt.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY')
$learnSets=$pt.Contains('_v740842LearnedUiBinkLumaAddresses') -and $pt.Contains('_v740842LearnedUiBinkChromaAddresses')
$applied=$it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY') -and $pt.Contains('SHARPEMU_V74_0_86_1_2_UI_BINK_DISCOVERY_LEARN')

Write-Host "$script:Tag RepositoryRoot=$repo"
Write-Host "$script:Tag ImeSHA256=$(Sha $ime)"
Write-Host "$script:Tag PresenterSHA256=$(Sha $presenter)"
Write-Host "$script:Tag base_v74086_ime=$baseIme"
Write-Host "$script:Tag typed_dcc_v86=$typed"
Write-Host "$script:Tag frame_ownership_v8421=$frame"
Write-Host "$script:Tag sticky_plane_v8421=$sticky"
Write-Host "$script:Tag learned_plane_sets_v8421=$learnSets"

if($applied){
    Write-Host "$script:Tag State=AlreadyApplied Ready=0 Applied=1" -ForegroundColor Yellow
    exit 10
}

if(-not $baseIme -or -not $typed -or -not $frame -or -not $sticky -or -not $learnSets){
    Write-Host "$script:Tag [ERROR] Accumulated source does not match the V74.0.86 + V74.0.84.2.1 baseline." -ForegroundColor Red
    exit 2
}

Write-Host "$script:Tag V86.1.1 failure avoided: no exact return anchor and no PumpHostMovieFrame repatch." -ForegroundColor Cyan
Write-Host "$script:Tag New strategy: learn the discovered Y/UV pair immediately after the four host-movie mapping assignments." -ForegroundColor Cyan
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
