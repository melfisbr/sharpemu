Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Resolve-SharpEmuRepoRoot {
    param([string]$RepositoryRoot)

    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $candidate = [System.IO.Path]::GetFullPath($RepositoryRoot)
        if ((Test-Path (Join-Path $candidate "SharpEmu.slnx")) -and
            (Test-Path (Join-Path $candidate "src\SharpEmu.Libs\Agc\AgcExports.cs"))) {
            return $candidate
        }
        throw "RepositoryRoot nao aponta para a raiz do SharpEmu: $candidate"
    }

    $cursor = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    for ($i = 0; $i -lt 8; $i++) {
        if ((Test-Path (Join-Path $cursor "SharpEmu.slnx")) -and
            (Test-Path (Join-Path $cursor "src\SharpEmu.Libs\Agc\AgcExports.cs"))) {
            return $cursor
        }
        $parent = [System.IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }

    throw "Nao foi possivel localizar a raiz do SharpEmu. Execute a partir do repositorio ou passe -RepositoryRoot."
}

function Get-PackageRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

function Get-AgcTarget {
    param([string]$RepositoryRoot)
    return Join-Path $RepositoryRoot "src\SharpEmu.Libs\Agc\AgcExports.cs"
}

function Get-WaitRegistryTarget {
    param([string]$RepositoryRoot)
    return Join-Path $RepositoryRoot "src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs"
}

function Read-Utf8Text {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

function Normalize-Lf {
    param([string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-MethodSlice {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$MethodName,
        [int]$MaxChars = 22000
    )
    $normalized = Normalize-Lf $Text
    $needle = $MethodName + "("
    $start = $normalized.IndexOf($needle, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return $null }
    $lineStart = $normalized.LastIndexOf("`n", $start)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
    $take = [Math]::Min($MaxChars, $normalized.Length - $lineStart)
    return $normalized.Substring($lineStart, $take)
}

function Test-ContainsAll {
    param([string]$Text, [string[]]$Needles)
    foreach ($needle in $Needles) {
        if (-not $Text.Contains($needle)) { return $false }
    }
    return $true
}
