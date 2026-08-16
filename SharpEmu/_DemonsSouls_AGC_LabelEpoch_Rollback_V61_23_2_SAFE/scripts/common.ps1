param()
function Resolve-RepoRoot([string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $p = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    } else {
        $p = (Resolve-Path $RepositoryRoot).Path
    }
    return $p
}
