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
    param(
        [string]$Text,
        [string]$Pattern
    )

    if ($null -eq $Text -or $null -eq $Pattern) {
        return $false
    }

    return $Text.IndexOf($Pattern, [StringComparison]::Ordinal) -ge 0
}

function Get-PackageRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Write-Utf8Lines {
    param(
        [string]$Path,
        [System.Collections.IEnumerable]$Lines
    )

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $list.Add([string]$line)
    }

    [IO.File]::WriteAllLines(
        $Path,
        $list.ToArray(),
        [Text.UTF8Encoding]::new($false))
}
