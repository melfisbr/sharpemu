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
    param([string]$Text, [string]$Pattern)

    if ($null -eq $Text -or $null -eq $Pattern) {
        return $false
    }

    return $Text.IndexOf($Pattern, [StringComparison]::Ordinal) -ge 0
}

function Insert-BeforeUnique {
    param(
        [string]$Text,
        [string]$Anchor,
        [string]$Insertion,
        [string]$Name
    )

    $first = $Text.IndexOf($Anchor, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw ('[V73.4] Patch anchor missing ({0}): {1}' -f $Name, $Anchor)
    }

    $second = $Text.IndexOf(
        $Anchor,
        $first + $Anchor.Length,
        [StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw ('[V73.4] Patch anchor is not unique ({0}).' -f $Name)
    }

    $nl = if ($Text.IndexOf("`r`n", [StringComparison]::Ordinal) -ge 0) { "`r`n" } else { "`n" }
    $normalizedInsertion = $Insertion.Replace("`r`n", "`n").Replace("`n", $nl)
    return $Text.Substring(0, $first) +
        $normalizedInsertion +
        $nl +
        $Text.Substring($first)
}

function Insert-AfterUniqueLine {
    param(
        [string]$Text,
        [string]$AnchorLine,
        [string]$Insertion,
        [string]$Name
    )

    $first = $Text.IndexOf($AnchorLine, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw ('[V73.4] Patch anchor missing ({0}): {1}' -f $Name, $AnchorLine)
    }

    $second = $Text.IndexOf(
        $AnchorLine,
        $first + $AnchorLine.Length,
        [StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw ('[V73.4] Patch anchor is not unique ({0}).' -f $Name)
    }

    $lineEnd = $Text.IndexOf("`n", $first)
    if ($lineEnd -lt 0) {
        throw ('[V73.4] Anchor has no line ending ({0}).' -f $Name)
    }

    $nl = if ($lineEnd -gt 0 -and $Text[$lineEnd - 1] -eq "`r") { "`r`n" } else { "`n" }
    $normalizedInsertion = $Insertion.Replace("`r`n", "`n").Replace("`n", $nl)
    return $Text.Substring(0, $lineEnd + 1) +
        $normalizedInsertion +
        $nl +
        $Text.Substring($lineEnd + 1)
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
