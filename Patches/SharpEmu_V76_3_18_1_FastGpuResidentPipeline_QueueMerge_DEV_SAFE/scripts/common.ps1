$ErrorActionPreference = 'Stop'

$Tag = 'V76.3.18.1-FAST-GPU-RESIDENT-PIPELINE-QUEUE-MERGE'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$PackageRoot = Split-Path -Parent $PSScriptRoot

$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$CliPath = Join-Path $Repo $CliRel
$PresenterPath = Join-Path $Repo $PresenterRel
$AgcPath = Join-Path $Repo $AgcRel

function Fail([string]$Message) { throw "[$Tag] $Message" }

function Ensure-Repo {
    foreach($p in @($CliPath,$PresenterPath,$AgcPath,$Project)) {
        if(-not(Test-Path -LiteralPath $p -PathType Leaf)) {
            Fail "arquivo ausente: $p"
        }
    }
    New-Item -ItemType Directory -Force -Path $Patches | Out-Null
}

function Get-HashLower([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Utf8Preserve([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $bom=$bytes.Length-ge3 -and $bytes[0]-eq0xEF -and $bytes[1]-eq0xBB -and $bytes[2]-eq0xBF
    $off=if($bom){3}else{0}
    $txt=[Text.Encoding]::UTF8.GetString($bytes,$off,$bytes.Length-$off)
    [pscustomobject]@{Text=$txt;HasBom=$bom}
}

function Write-Utf8Preserve([string]$Path,[string]$Text,[bool]$HasBom) {
    $enc=New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
