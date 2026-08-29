$Tag='V76.3.20.3-BALANCED-DUAL-QUEUE-RECOVERY'
$ErrorActionPreference = 'Stop'

$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$CliRel = 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$Project = Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$CliPath = Join-Path $Repo $CliRel
$PresenterPath = Join-Path $Repo $PresenterRel
$AgcPath = Join-Path $Repo $AgcRel
$PackageRoot = Split-Path -Parent $PSScriptRoot

function Fail([string]$Message) {
    throw "[$Tag] $Message"
}

function Ensure-Repo {
    foreach ($p in @($CliPath,$PresenterPath,$AgcPath,$Project)) {
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
    $bytes=[IO.File]::ReadAllBytes($Path)
    $bom=$bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF
    $off=if($bom){3}else{0}
    [pscustomobject]@{
        Text=[Text.Encoding]::UTF8.GetString($bytes,$off,$bytes.Length-$off)
        HasBom=$bom
    }
}

function Write-Utf8Preserve([string]$Path,[string]$Text,[bool]$HasBom) {
    $enc=New-Object System.Text.UTF8Encoding($HasBom)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}

function Insert-FinalApplyBlock(
    [string]$Text,
    [string]$Block,
    [string]$Marker) {

    if ($Text.Contains($Marker)) {
        return $Text
    }

    $anchorCrLf = "    }`r`n`r`n    private static bool IsDemonsSoulsLaunch()"
    $anchorLf   = "    }`n`n    private static bool IsDemonsSoulsLaunch()"

    $pos = $Text.IndexOf($anchorCrLf,[StringComparison]::Ordinal)
    if ($pos -lt 0) {
        $pos = $Text.IndexOf($anchorLf,[StringComparison]::Ordinal)
    }
    if ($pos -lt 0) {
        Fail 'tail anchor de DemonsSoulsGpuQueueEnvelope.Apply() ausente'
    }

    $nl=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
    $normalized=$Block.Replace("`r`n","`n").Replace("`r","`n")
    if($nl -eq "`r`n"){$normalized=$normalized.Replace("`n","`r`n")}

    return $Text.Insert($pos,$normalized + $nl)
}

function New-Backup([string]$Prefix,[string[]]$Files) {
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $root=Join-Path $Patches ($Prefix + "_PRE_SOURCE_" + $stamp)
    $zip=Join-Path $Patches ($Prefix + "_PRE_SOURCE_" + $stamp + ".zip")

    foreach($rel in $Files) {
        $src=Join-Path $Repo $rel
        $dst=Join-Path $root $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent)|Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    Compress-Archive -Path (Join-Path $root '*') -DestinationPath $zip -CompressionLevel Optimal -Force
    [pscustomobject]@{Root=$root;Zip=$zip;Stamp=$stamp}
}

function Restore-Backup($Backup,[string[]]$Files) {
    foreach($rel in $Files) {
        $src=Join-Path $Backup.Root $rel
        $dst=Join-Path $Repo $rel
        if(Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

function Build-Debug([string]$Stamp,[string]$Prefix) {
    $restoreLog=Join-Path $Patches ($Prefix + "_DEV_RESTORE_" + $Stamp + ".log")
    $buildLog=Join-Path $Patches ($Prefix + "_DEV_BUILD_" + $Stamp + ".log")

    Push-Location $Repo
    try {
        & dotnet restore $Project -r win-x64 *>&1 | Tee-Object -FilePath $restoreLog
        if($LASTEXITCODE -ne 0){throw "restore falhou exit=$LASTEXITCODE"}

        & dotnet build $Project -c Debug -r win-x64 --no-restore *>&1 |
            Tee-Object -FilePath $buildLog
        if($LASTEXITCODE -ne 0){throw "build Debug falhou exit=$LASTEXITCODE"}
    }
    finally {
        Pop-Location
    }
    return $buildLog
}
