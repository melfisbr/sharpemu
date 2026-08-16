Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepositoryRoot {
    param([string]$RepositoryRoot)

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    }

    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Test-TextContains {
    param(
        [string]$Text,
        [string]$Pattern
    )

    if ($null -eq $Text -or $null -eq $Pattern) {
        return $false
    }

    return ($Text.IndexOf($Pattern, [StringComparison]::Ordinal) -ge 0)
}
