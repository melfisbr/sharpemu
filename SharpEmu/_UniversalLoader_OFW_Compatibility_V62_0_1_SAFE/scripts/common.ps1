Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-Repo([string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    }
    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Test-ContainsOrdinal([string]$Text,[string]$Pattern) {
    if ($null -eq $Text -or $null -eq $Pattern) { return $false }
    return $Text.IndexOf($Pattern,[StringComparison]::Ordinal) -ge 0
}
