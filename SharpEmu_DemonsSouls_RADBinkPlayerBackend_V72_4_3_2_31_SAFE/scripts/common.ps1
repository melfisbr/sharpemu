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
        throw "[V72.4.3.2.31] Invalid repository root: $root"
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
        $bom =
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
    }

    $raw = [IO.File]::ReadAllText($Path)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }

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
        throw "[V72.4.3.2.31] Anchor missing: $Label"
    }

    $second = $Text.IndexOf(
        $Old,
        $first + $Old.Length,
        [StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "[V72.4.3.2.31] Anchor ambiguous: $Label"
    }

    return $Text.Substring(0,$first) +
        $New +
        $Text.Substring($first + $Old.Length)
}

function Find-RadVideo64 {
    if (-not [string]::IsNullOrWhiteSpace($env:SHARPEMU_RADVIDEO64) -and
        (Test-Path -LiteralPath $env:SHARPEMU_RADVIDEO64 -PathType Leaf) -and
        [IO.Path]::GetFileName($env:SHARPEMU_RADVIDEO64) -ieq "radvideo64.exe")
    {
        return (Resolve-Path -LiteralPath $env:SHARPEMU_RADVIDEO64).Path
    }

    $command = Get-Command radvideo64.exe -ErrorAction SilentlyContinue

    if ($null -ne $command -and
        -not [string]::IsNullOrWhiteSpace($command.Source) -and
        (Test-Path -LiteralPath $command.Source -PathType Leaf))
    {
        return (Resolve-Path -LiteralPath $command.Source).Path
    }

    try {
        $running =
            Get-CimInstance Win32_Process `
                -Filter "Name='radvideo64.exe'" `
                -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath)
            } |
            Select-Object -First 1

        if ($null -ne $running -and
            (Test-Path -LiteralPath $running.ExecutablePath -PathType Leaf))
        {
            return (Resolve-Path -LiteralPath $running.ExecutablePath).Path
        }
    }
    catch {
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($base in @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        (Join-Path $env:LOCALAPPDATA "Programs")
    )) {
        if ([string]::IsNullOrWhiteSpace($base)) {
            continue
        }

        $candidates.Add((Join-Path $base "RAD Video Tools\radvideo64.exe"))
        $candidates.Add((Join-Path $base "RADGameTools\radvideo64.exe"))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($searchRoot in @(
        (Join-Path $env:USERPROFILE "Downloads"),
        (Join-Path $env:USERPROFILE "Desktop")
    )) {
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
            continue
        }

        try {
            $found =
                Get-ChildItem `
                    -LiteralPath $searchRoot `
                    -Filter "radvideo64.exe" `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($null -ne $found) {
                return $found.FullName
            }
        }
        catch {
        }
    }

    return $null
}
