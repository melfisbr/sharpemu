Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Tag = '[DEMONS TITLE-CHAIN AUDIO FENCE V1.1.13]'

function Write-Step([string]$Message) {
    Write-Host "$script:Tag $Message"
}

function Get-PackageRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Test-IsSharpEmuRepoRoot([string]$Candidate) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $false
    }

    return [bool](
        (Test-Path -LiteralPath (Join-Path $Candidate 'src') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Candidate 'src\SharpEmu.Libs') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Candidate 'src\SharpEmu.GUI') -PathType Container)
    )
}

function Get-RepoRoot {
    $cursor = [System.IO.DirectoryInfo](Get-PackageRoot)
    $checkedPaths = New-Object System.Collections.Generic.List[string]

    for ($depth = 0; $null -ne $cursor -and $depth -lt 12; $depth++) {
        $candidate = $cursor.FullName
        $checkedPaths.Add($candidate)

        if (Test-IsSharpEmuRepoRoot $candidate) {
            Write-Step "RepositoryRootDetected=$candidate"
            Write-Step "RepositoryRootDepth=$depth"
            return $candidate
        }

        $cursor = $cursor.Parent
    }

    throw "$script:Tag SharpEmu repository root not found. Checked:`n$($checkedPaths -join "`n")"
}

function Find-UniqueSourceFile(
    [string]$Repo,
    [string]$FileName)
{
    $matches = @(
        Get-ChildItem -LiteralPath (Join-Path $Repo 'src') `
            -Recurse -File -Filter $FileName -ErrorAction Stop
    )

    if ($matches.Count -ne 1) {
        $found = if ($matches.Count -eq 0) {
            '<none>'
        }
        else {
            ($matches | ForEach-Object { $_.FullName }) -join "`n"
        }

        throw "$script:Tag Expected exactly one '$FileName' under src; found $($matches.Count).`n$found"
    }

    return $matches[0].FullName
}

function Find-GuiProject([string]$Repo) {
    $preferred = Join-Path $Repo 'src\SharpEmu.GUI\SharpEmu.GUI.csproj'
    if (Test-Path -LiteralPath $preferred -PathType Leaf) {
        return $preferred
    }

    $matches = @(
        Get-ChildItem -LiteralPath (Join-Path $Repo 'src\SharpEmu.GUI') `
            -Recurse -File -Filter '*.csproj'
    )

    if ($matches.Count -ne 1) {
        throw "$script:Tag Could not identify unique SharpEmu.GUI csproj."
    }

    return $matches[0].FullName
}

function Invoke-GuiBuild([string]$Repo) {
    $project = Find-GuiProject $Repo
    Write-Step "GuiProject=$project"

    & dotnet build $project -c Debug -r win-x64
    if ($LASTEXITCODE -ne 0) {
        throw "$script:Tag Build failed with exit code $LASTEXITCODE."
    }
}

function Get-HashSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Find-MatchingBraceIndex(
    [string]$Text,
    [int]$OpenBraceIndex)
{
    if ($OpenBraceIndex -lt 0 -or
        $OpenBraceIndex -ge $Text.Length -or
        $Text[$OpenBraceIndex] -ne '{') {
        throw "$script:Tag Invalid opening brace index: $OpenBraceIndex"
    }

    $depth = 0
    $inString = $false
    $inChar = $false
    $escape = $false
    $lineComment = $false
    $blockComment = $false

    for ($i = $OpenBraceIndex; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) {
            $Text[$i + 1]
        }
        else {
            [char]0
        }

        if ($lineComment) {
            if ($c -eq "`n") {
                $lineComment = $false
            }
            continue
        }

        if ($blockComment) {
            if ($c -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $i++
            }
            continue
        }

        if ($inString) {
            if ($escape) {
                $escape = $false
                continue
            }

            if ($c -eq '\') {
                $escape = $true
                continue
            }

            if ($c -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($inChar) {
            if ($escape) {
                $escape = $false
                continue
            }

            if ($c -eq '\') {
                $escape = $true
                continue
            }

            if ($c -eq "'") {
                $inChar = $false
            }
            continue
        }

        if ($c -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $i++
            continue
        }

        if ($c -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $i++
            continue
        }

        if ($c -eq '"') {
            $inString = $true
            continue
        }

        if ($c -eq "'") {
            $inChar = $true
            continue
        }

        if ($c -eq '{') {
            $depth++
        }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $i
            }
        }
    }

    throw "$script:Tag Matching closing brace not found."
}

function Find-MethodRegion(
    [string]$Text,
    [string]$Pattern,
    [string]$Name)
{
    $match = [regex]::Match(
        $Text,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    if (-not $match.Success) {
        throw "$script:Tag Structural method declaration not found: $Name"
    }

    $open = $Text.IndexOf(
        '{',
        $match.Index,
        [StringComparison]::Ordinal)

    if ($open -lt 0) {
        throw "$script:Tag Opening brace missing: $Name"
    }

    $close = Find-MatchingBraceIndex `
        -Text $Text `
        -OpenBraceIndex $open

    return [ordered]@{
        Match = $match
        OpenBrace = $open
        CloseBrace = $close
    }
}

function Get-PatchesRoot {
    $packageRoot = Get-PackageRoot
    return (Split-Path -Parent $packageRoot)
}
