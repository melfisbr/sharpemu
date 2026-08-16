Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    }
    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Test-ContainsOrdinal {
    param([string]$Text, [string]$Pattern)
    if ($null -eq $Text -or $null -eq $Pattern) {
        return $false
    }
    return $Text.IndexOf($Pattern, [StringComparison]::Ordinal) -ge 0
}

function Insert-LineAfterFirstMatch {
    param(
        [string]$Text,
        [string]$RegexPattern,
        [string]$NewLineText
    )

    $match = [regex]::Match(
        $Text,
        $RegexPattern,
        [Text.RegularExpressions.RegexOptions]::Multiline)

    if (-not $match.Success) {
        throw ('Patch anchor not found: {0}' -f $RegexPattern)
    }

    $lineBreak = if ($Text.IndexOf("`r`n", [StringComparison]::Ordinal) -ge 0) { "`r`n" } else { "`n" }
    $indentMatch = [regex]::Match($match.Value, '^\s*')
    $indent = $indentMatch.Value
    $replacement = $match.Value + $lineBreak + $indent + $NewLineText

    return $Text.Substring(0, $match.Index) +
        $replacement +
        $Text.Substring($match.Index + $match.Length)
}

function Get-PackageRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
