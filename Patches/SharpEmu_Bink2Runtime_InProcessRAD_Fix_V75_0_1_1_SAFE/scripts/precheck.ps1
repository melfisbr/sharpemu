param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
Assert-ManagedNativeBackend

Write-Tag 'SourceMutation=NONE'
Write-Tag 'ExternalRADFallback=PRESERVED'
Write-Tag 'UIBinkPolicy=zero-embedded-audio movies may use native-rad'
Write-Tag 'EmbeddedAudioPolicy=native adapter advertises no audio capability; managed backend rejects tracks>0 and falls back external RAD'
Write-Tag 'PRECHECK PASSED'
