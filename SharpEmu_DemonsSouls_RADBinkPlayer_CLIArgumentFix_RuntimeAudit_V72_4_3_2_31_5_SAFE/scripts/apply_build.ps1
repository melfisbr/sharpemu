param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.5] RAD player disappeared after precheck."
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"
$radSource = Join-Path $root $radRel
$configFile = Join-Path $root $configRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (
    ".sharpemu-hotfix-backup\RADBinkPlayerCLIArgumentFix_V72_4_3_2_31_5_" + $stamp)

$dest = Join-Path $backup $radRel
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
Copy-Item -LiteralPath $radSource -Destination $dest -Force

$configPreviouslyExisted = Test-Path -LiteralPath $configFile -PathType Leaf
if ($configPreviouslyExisted) {
    $destConfig = Join-Path $backup $configRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destConfig) | Out-Null
    Copy-Item -LiteralPath $configFile -Destination $destConfig -Force
}

try {
    Copy-Item `
        -LiteralPath (Join-Path $packageRoot "payload\RadBinkExternalPlaybackV7243231.cs") `
        -Destination $radSource `
        -Force

    $radText = Read-Normalized -Path $radSource

    foreach ($marker in @(
        "V72.4.3.2.31.5",
        "RAD_BINKPLAY_CLI_FIX",
        'start.ArgumentList.Add("binkplay");',
        'start.ArgumentList.Add(moviePath);',
        "bink2.rad_command"
    )) {
        if (-not $radText.Contains($marker)) {
            throw "[V72.4.3.2.31.5] Corrected RAD source marker missing: $marker"
        }
    }

    if ($radText.Contains('start.ArgumentList.Add("/#");')) {
        throw "[V72.4.3.2.31.5] Invalid V31.4 BinkPlay '/#' argument is still present."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.5] Building SharpEmu.Libs..."
        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.5] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31.5] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.5] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $configDir = Split-Path -Parent $configFile
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    [IO.File]::WriteAllText(
        $configFile,
        $radPath,
        (New-Object Text.UTF8Encoding($false)))

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\RADBinkPlayerCLIArgumentFix_V72_4_3_2_31_5_LAST.txt"
    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31.5] RAD_PLAYER=" + $radPath)
    Write-Host "[V72.4.3.2.31.5] SUCCESS: BinkPlay command repaired to 'radvideo64.exe binkplay <movie>'." -ForegroundColor Green
    Write-Host "[V72.4.3.2.31.5] IMPORTANT: this is still an external-process bridge; RUN_6 audits installed RAD runtime files for true in-process integration."
    Write-Host ("[V72.4.3.2.31.5] Backup: " + $backup)
}
catch {
    $saved = Join-Path $backup $radRel
    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        Copy-Item -LiteralPath $saved -Destination $radSource -Force
    }

    $savedConfig = Join-Path $backup $configRel
    if ($configPreviouslyExisted -and (Test-Path -LiteralPath $savedConfig -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configFile) | Out-Null
        Copy-Item -LiteralPath $savedConfig -Destination $configFile -Force
    }
    elseif ((-not $configPreviouslyExisted) -and (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        Remove-Item -LiteralPath $configFile -Force
    }

    Write-Host ("[V72.4.3.2.31.5] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.5] Restored RAD source from: " + $backup) -ForegroundColor Yellow
    throw
}
