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
        throw "[V72.4.3.2.28] Invalid repository root: $root"
    }

    return $root
}

function Read-Normalized {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path).Replace("`r`n","`n").Replace("`r","`n")
}

function Get-TextFormat {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $false
    if ($bytes.Length -ge 3) {
        $bom = $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    }

    $raw = [IO.File]::ReadAllText($Path)
    $nl = "`n"
    if ($raw.Contains("`r`n")) {
        $nl = "`r`n"
    }

    return [pscustomobject]@{
        HasBom = $bom
        NewLine = $nl
    }
}

function Write-Normalized {
    param([string]$Path,[string]$Text,$Format)

    $enc = New-Object Text.UTF8Encoding([bool]$Format.HasBom)
    [IO.File]::WriteAllText(
        $Path,
        $Text.Replace("`n",$Format.NewLine),
        $enc)
}

function Replace-ExactOnce {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)

    $first = $Text.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "[V72.4.3.2.28] Anchor missing: $Label"
    }

    $second = $Text.IndexOf(
        $Old,
        $first + $Old.Length,
        [StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "[V72.4.3.2.28] Anchor ambiguous: $Label"
    }

    return $Text.Substring(0,$first) +
        $New +
        $Text.Substring($first + $Old.Length)
}
