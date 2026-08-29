$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.21.3.1.1.2-STANDALONE-PRECHECK-FIX-AUTHORITATIVE-SYNC512-DEV-SAFE'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$BackendRel = 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$CliPath = Join-Path $Repo $CliRel
$PresenterPath = Join-Path $Repo $PresenterRel
$AgcPath = Join-Path $Repo $AgcRel
$BackendPath = Join-Path $Repo $BackendRel

function Fail([string]$Message) { throw "[$Tag] $Message" }
function Ensure-Repo {
    foreach ($p in @($CliPath,$PresenterPath,$AgcPath,$BackendPath,$Project)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Fail "arquivo ausente: $p" }
    }
    New-Item -ItemType Directory -Force -Path $Patches | Out-Null
}
function Get-HashLower([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Utf8Preserve([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString($bytes,$offset,$bytes.Length-$offset)
    [pscustomobject]@{ Text=$text; HasBom=$hasBom }
}
function Write-Utf8Preserve([string]$Path,[string]$Text,[bool]$HasBom) {
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
