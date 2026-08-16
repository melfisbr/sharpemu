Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$RepositoryRoot)

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = (Get-Location).Path
    }

    $candidate = $RepositoryRoot.Trim().Trim('"').TrimEnd('\','/')
    $root = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path

    if (-not (Test-Path -LiteralPath (Join-Path $root "src") -PathType Container)) {
        throw "[V72.4.3.2.27.0.1] Invalid repository root: $root"
    }

    return $root
}

function Read-Normalized {
    param([string]$Path)

    $text = [IO.File]::ReadAllText($Path)
    return $text.Replace("`r`n","`n").Replace("`r","`n")
}

function Get-TextFormat {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $false

    if ($bytes.Length -ge 3) {
        $hasBom =
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
    }

    $raw = [IO.File]::ReadAllText($Path)
    $newLine = "`n"
    if ($raw.Contains("`r`n")) {
        $newLine = "`r`n"
    }

    return [pscustomobject]@{
        HasBom = $hasBom
        NewLine = $newLine
    }
}

function Write-Normalized {
    param(
        [string]$Path,
        [string]$Text,
        $Format
    )

    $enc = New-Object Text.UTF8Encoding([bool]$Format.HasBom)
    $output = $Text.Replace("`n",$Format.NewLine)
    [IO.File]::WriteAllText($Path,$output,$enc)
}
