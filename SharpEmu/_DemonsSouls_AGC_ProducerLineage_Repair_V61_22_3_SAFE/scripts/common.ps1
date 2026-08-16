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

function Get-MethodDeclarationSlice {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$MethodName,
        [int]$MaxChars = 40000
    )

    # V61.22.3: never search for the first bare "MethodName(" occurrence.
    # AgcExports.cs calls ApplySubmittedWriteData before declaring it, so the
    # V61.22.1 detector could inspect a call-site and report a false negative.
    # Anchor on a private-static method declaration and stop at the next
    # private-static declaration at the same class indentation.
    $normalized = Normalize-Lf $Text
    $declarationNeedles = @(
        "    private static void $MethodName(",
        "    private static bool $MethodName(",
        "    private static int $MethodName(",
        "    private static uint $MethodName(",
        "    private static ulong $MethodName("
    )

    $start = -1
    foreach ($needle in $declarationNeedles) {
        $candidate = $normalized.IndexOf($needle, [System.StringComparison]::Ordinal)
        if ($candidate -ge 0 -and ($start -lt 0 -or $candidate -lt $start)) {
            $start = $candidate
        }
    }
    if ($start -lt 0) { return $null }

    $next = $normalized.IndexOf("`n    private static ", $start + 1, [System.StringComparison]::Ordinal)
    if ($next -lt 0) {
        $take = [Math]::Min($MaxChars, $normalized.Length - $start)
        return $normalized.Substring($start, $take)
    }

    $length = $next - $start
    if ($length -gt $MaxChars) { $length = $MaxChars }
    return $normalized.Substring($start, $length)
}

function Test-ContainsAll {
    param([string]$Text, [string[]]$Needles)
    foreach ($needle in $Needles) {
        if (-not $Text.Contains($needle)) { return $false }
    }
    return $true
}
