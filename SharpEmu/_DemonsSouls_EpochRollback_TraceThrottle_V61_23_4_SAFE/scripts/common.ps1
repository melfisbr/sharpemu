Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot([string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    }
    return (Resolve-Path $RepositoryRoot).Path
}
