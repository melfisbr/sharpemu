Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$RepositoryRoot)

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    }

    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Get-PackageRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
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

function Write-Utf8Lines {
    param(
        [string]$Path,
        [System.Collections.IEnumerable]$Lines
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $items.Add([string]$line)
    }

    [IO.File]::WriteAllLines(
        $Path,
        $items.ToArray(),
        [Text.UTF8Encoding]::new($false))
}

function Get-MaxCounterFromLines {
    param(
        [string[]]$Lines,
        [string]$Field
    )

    $max = 0L
    $pattern = '\b' + [regex]::Escape($Field) + '=(\d+)'
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) {
            continue
        }

        $value = 0L
        if ([long]::TryParse($match.Groups[1].Value, [ref]$value) -and
            $value -gt $max) {
            $max = $value
        }
    }

    return $max
}
