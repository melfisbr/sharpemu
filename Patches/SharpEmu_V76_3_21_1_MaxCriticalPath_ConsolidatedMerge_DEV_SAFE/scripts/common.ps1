$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.21.1-MAX-CRITICAL-PATH-CONSOLIDATED-MERGE'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$AgcPath = Join-Path $Repo $AgcRel
$PresenterPath = Join-Path $Repo $PresenterRel
$CliPath = Join-Path $Repo $CliRel

function Fail([string]$Message) {
    throw "[$Tag] $Message"
}

function Ensure-Repo {
    foreach ($p in @($AgcPath, $PresenterPath, $CliPath, $Project)) {
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

function Find-MethodRange(
    [string]$Text,
    [string]$Signature,
    [string]$Label) {

    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) {
        Fail "metodo ausente: $Label"
    }

    $brace = $Text.IndexOf('{', $start)
    if ($brace -lt 0) {
        Fail "abertura de metodo ausente: $Label"
    }

    $depth = 0
    for ($i = $brace; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '{') {
            $depth++
        }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return [pscustomobject]@{
                    Start = $start
                    End = $i + 1
                }
            }
        }
    }

    Fail "fim de metodo nao encontrado: $Label"
}

function Replace-InMethodOnce(
    [string]$Text,
    [string]$Signature,
    [string]$Old,
    [string]$New,
    [string]$Label) {

    $range = Find-MethodRange $Text $Signature $Label
    $segment = $Text.Substring(
        $range.Start,
        $range.End - $range.Start)

    $first = $segment.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        Fail "anchor interno ausente: $Label"
    }

    $second = $segment.IndexOf(
        $Old,
        $first + $Old.Length,
        [StringComparison]::Ordinal)

    if ($second -ge 0) {
        Fail "anchor interno nao-unico: $Label"
    }

    $segment = $segment.Remove($first, $Old.Length).Insert($first, $New)

    return $Text.Remove(
        $range.Start,
        $range.End - $range.Start).Insert(
            $range.Start,
            $segment)
}
