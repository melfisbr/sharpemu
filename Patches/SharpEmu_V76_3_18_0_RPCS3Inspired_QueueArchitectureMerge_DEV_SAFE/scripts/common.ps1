$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.18.0-RPCS3-INSPIRED-QUEUE-ARCHITECTURE-MERGE'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$PresenterPath = Join-Path $Repo $PresenterRel
$AgcPath = Join-Path $Repo $AgcRel
$CliPath = Join-Path $Repo $CliRel

$ExpectedPresenterBaseline = 'f7a98ce40383bbff5e5e030fff119476dbcfb0c27006cf417a5e3f0cf886746b'
$ExpectedPresenterResult = '712199a608bac7782f24fd35a52cce9071383638de61e0135d67d08bf85d92a6'

function Fail([string]$Message) {
    throw "[$Tag] $Message"
}

function Ensure-Repo {
    foreach ($p in @($PresenterPath, $AgcPath, $CliPath, $Project)) {
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
