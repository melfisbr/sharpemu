param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "HostMovieBridge V1.1.13 title-chain lifecycle hook already installed."
    exit 0
}

foreach ($required in @(
    'AttachMovieLocked',
    'logo_intro_loop.bk2',
    'TITLE_LOOP_AUDIO'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag HostMovieBridge accumulated marker missing: $required"
    }
}

$attachPattern =
    '(?ms)^[ \t]*private[ \t]+static[ \t]+void[ \t]+AttachMovieLocked[ \t]*\([ \t\r\n]*string[ \t]+hostPath[ \t]*,[ \t\r\n]*MovieMode[ \t]+mode[ \t\r\n]*\)[ \t\r\n]*\{'

$attachRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $attachPattern `
    -Name 'AttachMovieLocked'

$hook = @'

        // SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13
        // Execute before mode rewriting and before any host-audio probe.
        // This covers UI_BINK_INTERNAL where host_audio_probe=False.
        BinkDemonSoulsIntroAudioV7243227.NotifyMovieAttachV1113(
            hostPath);
'@

$text = $text.Insert(
    $attachRegion.OpenBrace + 1,
    $hook)

foreach ($required in @(
    'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13',
    'NotifyMovieAttachV1113',
    'Execute before mode rewriting and before any host-audio probe.'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag HostMovieBridge V1.1.13 post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "HostMovieBridge title-chain audio lifecycle hook installed."
