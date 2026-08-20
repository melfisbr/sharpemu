. "$PSScriptRoot\common.ps1"

$repo=RepoRoot
$ime=ImeDialogSource
$presenter=PresenterSource

try{
    Assert-V7408612 $repo
}
catch{
    Write-Host "$script:Tag [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$it=NL([IO.File]::ReadAllText($ime))
$pt=NL([IO.File]::ReadAllText($presenter))

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "ime_osk_overlay=$($it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY'))"
Write-Host "v8421_frame_ownership_preserved=$($pt.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP'))"
Write-Host "v8421_sticky_plane_preserved=$($pt.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY'))"
Write-Host "v86_typed_dcc_preserved=$($pt.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC'))"
Write-Host "discovery_learning_hook=$($pt.Contains('SHARPEMU_V74_0_86_1_2_UI_BINK_DISCOVERY_LEARN'))"
Write-Host "discovery_learning_luma=$($pt.Contains('_v740842LearnedUiBinkLumaAddresses.Add(lumaTexture.Address)'))"
Write-Host "discovery_learning_chroma=$($pt.Contains('_v740842LearnedUiBinkChromaAddresses.Add(chromaTexture.Address)'))"
Write-Host "PresenterSHA256=$(Sha $presenter)"
Write-Host "ImeSHA256=$(Sha $ime)"
Write-Host "build_artifact_exists=$(Test-Path -LiteralPath (ExePath))"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
