$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.21.3-GUEST-PROGRESS-RECOVERY-PERF-MERGE'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$CliPath = Join-Path $Repo $CliRel
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

function Fail([string]$m) {
    throw "[$Tag] $m"
}

function Ensure-Repo {
    foreach ($p in @($CliPath,$Project)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            Fail "arquivo ausente: $p"
        }
    }
    New-Item -ItemType Directory -Force -Path $Patches | Out-Null
}

function Read-Utf8Preserve([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and
              $bytes[0] -eq 0xEF -and
              $bytes[1] -eq 0xBB -and
              $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    [pscustomobject]@{
        Text = [Text.Encoding]::UTF8.GetString(
            $bytes, $offset, $bytes.Length - $offset)
        HasBom = $hasBom
    }
}

function Write-Utf8Preserve(
    [string]$Path,
    [string]$Text,
    [bool]$HasBom) {
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}

function HashLower([string]$p) {
    (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
}
