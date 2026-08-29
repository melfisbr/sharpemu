$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.18.5-ADAPTIVE-FULL-PERFORMANCE-MERGE'
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

$RequiredPresenterBaseline = '0fbac93116b63afd82cd921fa57c8bdfcd57623b1ede0ff568fcab9c355e7a25'

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

function Replace-IntConstantMinimum(
    [string]$Text,
    [string]$Name,
    [int]$Minimum) {

    $pattern =
        '(?m)^(?<indent>[ \t]*)private\s+const\s+int\s+' +
        [regex]::Escape($Name) +
        '\s*=\s*(?<value>\d+)\s*;[ \t]*$'

    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        Fail "constante Presenter ausente: $Name"
    }

    $old = [int]$match.Groups['value'].Value
    if ($old -ge $Minimum) {
        return [pscustomobject]@{
            Text = $Text
            Old = $old
            New = $old
        }
    }

    $replacement =
        $match.Groups['indent'].Value +
        "private const int $Name = $Minimum;"

    $updated =
        $Text.Substring(0, $match.Index) +
        $replacement +
        $Text.Substring($match.Index + $match.Length)

    [pscustomobject]@{
        Text = $updated
        Old = $old
        New = $Minimum
    }
}
