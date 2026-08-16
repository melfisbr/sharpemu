param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot

$cliProject = Join-Path $root "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
$runtimeTool = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$optimizedDir = Join-Path $root ".sharpemu-tools\bink2\optimized"
$optimizedTool = Join-Path $optimizedDir "nihav-tool-v27-native.exe"
$payload = Join-Path $packageRoot "payload\nihav-tool-native.exe"

$expectedHash = "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (".sharpemu-hotfix-backup\BinkV27RuntimeRepair_V72_4_3_2_27_0_1_" + $stamp)

$projectBackup = Join-Path $backup "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
$runtimeBackup = Join-Path $backup "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$optimizedBackup = Join-Path $backup ".sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $projectBackup) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeBackup) | Out-Null

Copy-Item -LiteralPath $cliProject -Destination $projectBackup -Force
Copy-Item -LiteralPath $runtimeTool -Destination $runtimeBackup -Force

$optimizedExisted = Test-Path -LiteralPath $optimizedTool -PathType Leaf
if ($optimizedExisted) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $optimizedBackup) | Out-Null
    Copy-Item -LiteralPath $optimizedTool -Destination $optimizedBackup -Force
}

try {
    $payloadHash = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($payloadHash -ne $expectedHash) {
        throw "[V72.4.3.2.27.0.1] Native payload hash mismatch."
    }

    New-Item -ItemType Directory -Force -Path $optimizedDir | Out-Null
    Copy-Item -LiteralPath $payload -Destination $optimizedTool -Force

    $optimizedHash = (Get-FileHash -LiteralPath $optimizedTool -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($optimizedHash -ne $expectedHash) {
        throw "[V72.4.3.2.27.0.1] Optimized source-tool hash mismatch."
    }

    $format = Get-TextFormat -Path $cliProject
    $text = Read-Normalized -Path $cliProject

    $oldSource = '$(MSBuildProjectDirectory)\..\..\.sharpemu-tools\bink2\src\nihav\nihav-tool\target\release\nihav-tool.exe'
    $newSource = '$(MSBuildProjectDirectory)\..\..\.sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe'

    if (-not $text.Contains($newSource)) {
        if (-not $text.Contains($oldSource)) {
            throw "[V72.4.3.2.27.0.1] Original NIHAV deploy path anchor not found."
        }

        $text = $text.Replace(
            '  <!-- V61.13.16.6_BINK_RUNTIME_DEPLOY -->',
            '  <!-- V61.13.16.6_BINK_RUNTIME_DEPLOY -->' + "`n" +
            '  <!-- V72.4.3.2.27.0.1 PERSISTENT_NATIVE_NIHAV_DEPLOY -->')

        $text = $text.Replace($oldSource,$newSource)
        Write-Normalized -Path $cliProject -Text $text -Format $format
    }

    $after = Read-Normalized -Path $cliProject
    if (-not $after.Contains("V72.4.3.2.27.0.1 PERSISTENT_NATIVE_NIHAV_DEPLOY")) {
        throw "[V72.4.3.2.27.0.1] Persistent deploy marker missing after patch."
    }
    if (-not $after.Contains($newSource)) {
        throw "[V72.4.3.2.27.0.1] Persistent optimized NIHAV source path missing after patch."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.27.0.1] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build "src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.27.0.1] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    # The build itself must now deploy the optimized tool through the patched
    # CopySharpEmuNihavToolV6113166 target. Copy once more only as a safety net,
    # then verify the final on-disk runtime hash after all build activity.
    if (-not (Test-Path -LiteralPath $runtimeTool -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeTool) | Out-Null
        Copy-Item -LiteralPath $optimizedTool -Destination $runtimeTool -Force
    }

    $finalHash = (Get-FileHash -LiteralPath $runtimeTool -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($finalHash -ne $expectedHash) {
        Write-Host "[V72.4.3.2.27.0.1] Build did not preserve native runtime; applying post-build safety copy." -ForegroundColor Yellow
        Copy-Item -LiteralPath $optimizedTool -Destination $runtimeTool -Force
        $finalHash = (Get-FileHash -LiteralPath $runtimeTool -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    if ($finalHash -ne $expectedHash) {
        throw "[V72.4.3.2.27.0.1] Final runtime NIHAV hash is still incorrect: $finalHash"
    }

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\BinkV27RuntimeRepair_V72_4_3_2_27_0_1_LAST.txt"
    [IO.File]::WriteAllText($pointer,$backup,(New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.27.0.1] FINAL_NIHAV_SHA256=" + $finalHash)
    Write-Host ("[V72.4.3.2.27.0.1] Backup: " + $backup)
    Write-Host "[V72.4.3.2.27.0.1] SUCCESS: future builds now deploy the native NIHAV and the runtime hash is correct." -ForegroundColor Green
}
catch {
    if (Test-Path -LiteralPath $projectBackup -PathType Leaf) {
        Copy-Item -LiteralPath $projectBackup -Destination $cliProject -Force
    }

    if (Test-Path -LiteralPath $runtimeBackup -PathType Leaf) {
        Copy-Item -LiteralPath $runtimeBackup -Destination $runtimeTool -Force
    }

    if ($optimizedExisted) {
        if (Test-Path -LiteralPath $optimizedBackup -PathType Leaf) {
            New-Item -ItemType Directory -Force -Path $optimizedDir | Out-Null
            Copy-Item -LiteralPath $optimizedBackup -Destination $optimizedTool -Force
        }
    }
    else {
        if (Test-Path -LiteralPath $optimizedTool -PathType Leaf) {
            Remove-Item -LiteralPath $optimizedTool -Force
        }
    }

    Write-Host ("[V72.4.3.2.27.0.1] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.27.0.1] Restored from: " + $backup) -ForegroundColor Yellow
    throw
}
