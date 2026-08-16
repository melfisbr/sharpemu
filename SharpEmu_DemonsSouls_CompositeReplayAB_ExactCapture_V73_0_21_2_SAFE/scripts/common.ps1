Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-SourceBase([string]$RepoRoot) {
    $repo=[IO.Path]::GetFullPath($RepoRoot)
    foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)) {
        $vp=[IO.Path]::Combine($candidate,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
        $ag=[IO.Path]::Combine($candidate,'SharpEmu.Libs\Agc\AgcExports.cs')
        if([IO.File]::Exists($vp) -and [IO.File]::Exists($ag)) {
            return $candidate
        }
    }
    throw 'Source layout not recognized.'
}

function Require-ReplaySwitch([string]$AgcPath) {
    $text=[IO.File]::ReadAllText($AgcPath)
    foreach($marker in @(
        'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',
        'PendingTargetlessDraws',
        'deferred_composite_suppressed'
    )) {
        if($text.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) {
            throw "AGC replay prerequisite missing: $marker"
        }
    }
}

function Write-Utf8NoBom([string]$Path,[string[]]$Lines) {
    [IO.File]::WriteAllLines(
        $Path,
        $Lines,
        [Text.UTF8Encoding]::new($false))
}
