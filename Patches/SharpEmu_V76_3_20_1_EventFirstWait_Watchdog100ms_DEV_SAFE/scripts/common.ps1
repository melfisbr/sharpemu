$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.20.1-EVENT-FIRST-WAIT-WATCHDOG'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$CliPath = Join-Path $Repo $CliRel
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

function Fail([string]$Message) {
    throw "[$Tag] $Message"
}

function Ensure-Repo {
    foreach ($p in @($CliPath, $Project)) {
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
        $bytes, $offset, $bytes.Length - $offset)
    [pscustomobject]@{ Text=$text; HasBom=$hasBom }
}

function Write-Utf8Preserve(
    [string]$Path,
    [string]$Text,
    [bool]$HasBom) {
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path, $Text, $enc)
}

function Insert-BeforeMarker(
    [string]$Text,
    [string]$MarkerNeedle,
    [string]$Block) {

    $pos = $Text.IndexOf($MarkerNeedle, [StringComparison]::Ordinal)
    if ($pos -lt 0) {
        Fail "runtime marker anchor ausente: $MarkerNeedle"
    }

    $consoleStart = $Text.LastIndexOf(
        '        Console.Error.WriteLine(',
        $pos,
        [StringComparison]::Ordinal)

    if ($consoleStart -lt 0) {
        Fail "Console.Error.WriteLine anchor ausente para $MarkerNeedle"
    }

    return $Text.Insert($consoleStart, $Block)
}
