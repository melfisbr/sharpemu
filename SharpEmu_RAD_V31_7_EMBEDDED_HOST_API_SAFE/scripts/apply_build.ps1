param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.7] RAD player disappeared after precheck."
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$apiRel = "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV72432317.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

$radSource = Join-Path $root $radRel
$apiSource = Join-Path $root $apiRel
$configFile = Join-Path $root $configRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (".sharpemu-hotfix-backup\RADEmbeddedHost_V72_4_3_2_31_7_" + $stamp)

$tracked = @($radRel,$apiRel)
$existed = @{}
foreach ($rel in $tracked) {
    $source = Join-Path $root $rel
    $existed[$rel] = Test-Path -LiteralPath $source -PathType Leaf
    if ($existed[$rel]) {
        $dest = Join-Path $backup $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
}

$configPreviouslyExisted = Test-Path -LiteralPath $configFile -PathType Leaf
if ($configPreviouslyExisted) {
    $destConfig = Join-Path $backup $configRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destConfig) | Out-Null
    Copy-Item -LiteralPath $configFile -Destination $destConfig -Force
}

try {
    Copy-Item -LiteralPath (Join-Path $packageRoot "payload\RadBinkExternalPlaybackV7243231.cs") -Destination $radSource -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot "payload\RadBinkEmbeddedHostApiV72432317.cs") -Destination $apiSource -Force

    $radText = Read-Normalized -Path $radSource
    $apiText = Read-Normalized -Path $apiSource

    foreach ($marker in @(
        "V72.4.3.2.31.7",
        "RadBinkEmbeddedHostApiV72432317.TryAttach",
        'start.ArgumentList.Add("/I2");',
        "external_window_forbidden=True",
        "anchor=rad-embedded-playback-ready",
        "BinkDemonSoulsIntroAudioV7243227.NotifyPresentationStarted"
    )) {
        if (-not $radText.Contains($marker)) {
            throw "[V72.4.3.2.31.7] RAD source marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "internal interface IRadBinkHostApi",
        "class RadBinkEmbeddedHostApiV72432317",
        "SetParent",
        "WsChild",
        "bink2.rad_host_attached",
        "render_location=sharpemu-child-window",
        "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS"
    )) {
        if (-not $apiText.Contains($marker)) {
            throw "[V72.4.3.2.31.7] Embedded host API marker missing: $marker"
        }
    }

    if ($radText.Contains('start.ArgumentList.Add("/#");')) {
        throw "[V72.4.3.2.31.7] Historical invalid BinkPlay '/#' argument returned."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.7] Building SharpEmu.Libs..."
        & dotnet.exe build "src\SharpEmu.Libs\SharpEmu.Libs.csproj" -c Debug --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.7] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31.7] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build "src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.7] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $configDir = Split-Path -Parent $configFile
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    [IO.File]::WriteAllText($configFile,$radPath,(New-Object Text.UTF8Encoding($false)))

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\RADEmbeddedHost_V72_4_3_2_31_7_LAST.txt"
    [IO.File]::WriteAllText($pointer,$backup,(New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31.7] RAD_PLAYER=" + $radPath)
    Write-Host "[V72.4.3.2.31.7] SUCCESS: embedded RAD host API installed; independent player window is forbidden; attract audio is anchored after host attachment." -ForegroundColor Green
    Write-Host ("[V72.4.3.2.31.7] Backup: " + $backup)
}
catch {
    foreach ($rel in $tracked) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel
        if ($existed[$rel] -and (Test-Path -LiteralPath $saved -PathType Leaf)) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
        elseif ((-not $existed[$rel]) -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            Remove-Item -LiteralPath $target -Force
        }
    }

    $savedConfig = Join-Path $backup $configRel
    if ($configPreviouslyExisted -and (Test-Path -LiteralPath $savedConfig -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configFile) | Out-Null
        Copy-Item -LiteralPath $savedConfig -Destination $configFile -Force
    }
    elseif ((-not $configPreviouslyExisted) -and (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        Remove-Item -LiteralPath $configFile -Force
    }

    Write-Host ("[V72.4.3.2.31.7] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.7] Restored source from: " + $backup) -ForegroundColor Yellow
    throw
}
