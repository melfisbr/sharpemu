param()
. (Join-Path $PSScriptRoot 'common.ps1')
$state=Get-BaselineState
$repo=Get-RepositoryRoot
$hostMovie=Get-SourcePath $script:Preserve.HostMovie.Rel
$videoOut=Get-SourcePath $script:Preserve.VideoOut.Rel
$hostMovieText=[IO.File]::ReadAllText($hostMovie)
$videoOutText=[IO.File]::ReadAllText($videoOut)
Write-Tag "BaselineState=$($state.State)"
Write-Tag "HostMovieUiBinkResourceContract=$($hostMovieText.Contains('These Binks are not fullscreen owner movies'))"
Write-Tag "HostMovieUiBinkClassifier=$($hostMovieText.Contains('IsDemonSoulsUiBinkCompositePathV740841'))"
Write-Tag "VideoOutSubmitFlipBoundary=$($videoOutText.Contains('sceVideoOutSubmitFlip'))"
Write-Tag "VideoOutGuestImageSubmit=$($videoOutText.Contains('TrySubmitGuestImage'))"
Write-Tag 'SOURCE LAYOUT CHECK PASSED'
