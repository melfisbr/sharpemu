param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$bridgeRel = "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$bridgePath = Join-Path $root $bridgeRel
$original = [IO.File]::ReadAllText($bridgePath)
$span = Get-CSharpMethodSpanV3178 -Text $original -Signature "private static void TryStartConfiguredBootSequence()"
if ($span.Start -lt 0) {
    throw "[V72.4.3.2.31.7.8] TryStartConfiguredBootSequence() disappeared after precheck."
}

$canonicalPath = Join-Path $packageRoot "patch\HostMovieBridge.TryStartConfiguredBootSequence.v3178.csfrag"
$canonical = [IO.File]::ReadAllText($canonicalPath).TrimEnd()
$alreadyCanonical = (Normalize-CSharpV3178 $span.Text) -eq (Normalize-CSharpV3178 $canonical)

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot = Join-Path $root (".sharpemu-hotfix-backup\RADGuestMediaHandoff_V72_4_3_2_31_7_8_" + $stamp)
$backupFile = Join-Path $backupRoot $bridgeRel
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null
Copy-Item -LiteralPath $bridgePath -Destination $backupFile -Force
$changed = $false

try {
    if (-not $alreadyCanonical) {
        $format = Get-TextFormat -Path $bridgePath
        $normalizedOriginal = $original.Replace("`r`n","`n").Replace("`r","`n")
        $normalizedSpan = Get-CSharpMethodSpanV3178 -Text $normalizedOriginal -Signature "private static void TryStartConfiguredBootSequence()"
        if ($normalizedSpan.Start -lt 0) {
            throw "[V72.4.3.2.31.7.8] Normalized boot-method span not found."
        }
        $fragment = $canonical.Replace("`r`n","`n").Replace("`r","`n")
        $newText = $normalizedOriginal.Remove($normalizedSpan.Start,$normalizedSpan.Length).Insert($normalizedSpan.Start,$fragment)
        Write-Normalized -Path $bridgePath -Text $newText -Format $format
        $changed = $true
        Write-Host "[V72.4.3.2.31.7.8] SOURCE PATCH APPLIED: host attract injection removed; canonical guest-driven boundary restored."
    }
    else {
        Write-Host "[V72.4.3.2.31.7.8] Canonical guest-media handoff already present; source rewrite not required."
    }

    $verify = [IO.File]::ReadAllText($bridgePath)
    $verifySpan = Get-CSharpMethodSpanV3178 -Text $verify -Signature "private static void TryStartConfiguredBootSequence()"
    if ($verifySpan.Start -lt 0 -or
        (Normalize-CSharpV3178 $verifySpan.Text) -ne (Normalize-CSharpV3178 $canonical)) {
        throw "[V72.4.3.2.31.7.8] Canonical method verification failed after write."
    }
    if ($verifySpan.Text.Contains("attract_movie.bk2")) {
        throw "[V72.4.3.2.31.7.8] attract_movie still exists inside host auto-boot method."
    }
    if (-not $verifySpan.Text.Contains("logo_intro_loop.bk2")) {
        throw "[V72.4.3.2.31.7.8] Canonical logo_intro_loop boundary missing."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.7.8] Building SharpEmu.Libs Debug..."
        & dotnet.exe build "src\SharpEmu.Libs\SharpEmu.Libs.csproj" -c Debug --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.7.8] SharpEmu.Libs build failed."
        }
        Write-Host "[V72.4.3.2.31.7.8] Building SharpEmu.CLI Debug win-x64..."
        & dotnet.exe build "src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.7.8] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\RADGuestMediaHandoff_V72_4_3_2_31_7_8_LAST.txt"
    [IO.File]::WriteAllText($pointer,$backupRoot,(New-Object Text.UTF8Encoding($false)))
    Write-Host "[V72.4.3.2.31.7.8] SUCCESS: RAD/hard gate preserved; attract_movie returned to guest/EBOOT ownership." -ForegroundColor Green
    Write-Host ("[V72.4.3.2.31.7.8] Backup: " + $backupRoot)
}
catch {
    if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
        Copy-Item -LiteralPath $backupFile -Destination $bridgePath -Force
    }
    Write-Host ("[V72.4.3.2.31.7.8] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.7.8] HostMovieBridge restored from: " + $backupRoot) -ForegroundColor Yellow
    throw
}
