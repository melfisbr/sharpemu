$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.21.2-GLOBAL-SNAPSHOT-BOUNDS-LOADING-CRASH-RECOVERY'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$PresenterPath = Join-Path $Repo $PresenterRel
$CliPath = Join-Path $Repo $CliRel

function Fail([string]$Message) {
    throw "[$Tag] $Message"
}

function Ensure-Repo {
    foreach ($p in @($PresenterPath, $CliPath, $Project)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            Fail "arquivo ausente: $p"
        }
    }
    New-Item -ItemType Directory -Force -Path $Patches | Out-Null
}

function Get-HashLower([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Utf8Preserve([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and
              $bytes[0] -eq 0xEF -and
              $bytes[1] -eq 0xBB -and
              $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString(
        $bytes,
        $offset,
        $bytes.Length - $offset)
    [pscustomobject]@{ Text=$text; HasBom=$hasBom }
}

function Write-Utf8Preserve(
    [string]$Path,
    [string]$Text,
    [bool]$HasBom) {
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path, $Text, $enc)
}

function Normalize-Newlines([string]$Text, [string]$NewLine) {
    $x = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($NewLine -eq "`n") {
        return $x
    }
    return $x.Replace("`n", $NewLine)
}

function Replace-Unique(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label) {

    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        Fail "anchor ausente: $Label"
    }

    $second = $Text.IndexOf(
        $Old,
        $first + $Old.Length,
        [StringComparison]::Ordinal)

    if ($second -ge 0) {
        Fail "anchor nao-unico: $Label"
    }

    return $Text.Remove($first, $Old.Length).Insert($first, $New)
}
