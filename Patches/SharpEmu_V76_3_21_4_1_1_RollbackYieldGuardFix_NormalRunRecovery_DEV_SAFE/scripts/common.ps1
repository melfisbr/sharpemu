$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.21.4.1.1-ROLLBACK-YIELD-GUARD-FIX-NORMAL-RUN-RECOVERY-DEV-SAFE'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$CliProfileRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$AgcPath = Join-Path $Repo $AgcRel
$PresenterPath = Join-Path $Repo $PresenterRel
$CliProfilePath = Join-Path $Repo $CliProfileRel
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

function Fail([string]$Message) { throw "[$Tag] $Message" }

function Ensure-Repo {
    foreach ($p in @($AgcPath,$PresenterPath,$CliProfilePath,$Project)) {
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
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString($bytes,$offset,$bytes.Length-$offset)
    [pscustomobject]@{ Text=$text; HasBom=$hasBom }
}

function Write-Utf8Preserve([string]$Path,[string]$Text,[bool]$HasBom) {
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}

function Copy-LiveFile([string]$Source,[string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
    $src = $null
    $dst = $null
    try {
        $src = [IO.File]::Open(
            $Source,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        $dst = [IO.File]::Open(
            $Destination,
            [IO.FileMode]::Create,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read
        )
        $src.CopyTo($dst)
        return $true
    }
    finally {
        if ($dst) { $dst.Dispose() }
        if ($src) { $src.Dispose() }
    }
}
