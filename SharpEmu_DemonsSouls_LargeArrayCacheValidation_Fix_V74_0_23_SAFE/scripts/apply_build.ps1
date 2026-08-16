param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot = Resolve-RepoRootV74023 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot
$agcPath = Get-AgcPathV74023 -Root $repoRoot
$hostMoviePath = Get-HostMoviePathV74023 -Root $repoRoot
$hostHashBefore = if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
$agcText = [System.IO.File]::ReadAllText($agcPath)
$state = Get-V23StateV74023 -Text $agcText
$backupDirectory = $null
$backupAgc = $null
if ($state -eq "Baseline") {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDirectory = [System.IO.Path]::Combine($repoRoot, ".sharpemu-hotfix-backup", "LargeArrayCacheTrust_V74_0_23_$stamp")
    [System.IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    $backupAgc = [System.IO.Path]::Combine($backupDirectory, "AgcExports.cs")
    Copy-Item -LiteralPath $agcPath -Destination $backupAgc -Force
    try {
        $patchedText = Convert-AgcV74023 -Text $agcText
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($agcPath, $patchedText, $utf8NoBom)
        $verifyText = [System.IO.File]::ReadAllText($agcPath)
        if ((Get-V23StateV74023 -Text $verifyText) -ne "Applied") { throw "[V74.0.23] Post-write AGC verification failed." }
        $hostHashAfter = if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
        if ($hostHashAfter -ne $hostHashBefore) { throw "[V74.0.23] HostMovieBridge changed unexpectedly." }
        Write-Host "[V74.0.23] SOURCE PATCH APPLIED: opt-in large-array resident-cache trust gate installed."
        Write-Host "[V74.0.23] Backup: $backupDirectory"
    }
    catch {
        if ($backupAgc -and [System.IO.File]::Exists($backupAgc)) { Copy-Item -LiteralPath $backupAgc -Destination $agcPath -Force }
        Write-Host "[V74.0.23] Apply failed; AgcExports.cs restored."
        throw
    }
}
else {
    Write-Host "[V74.0.23] Source correction already installed; build verification only."
}
try {
    Write-Host "[V74.0.23] Building Release win-x64..."
    Invoke-DotNetCheckedV74023 -Root $repoRoot -Arguments @("build", "src\SharpEmu.CLI\SharpEmu.CLI.csproj", "-c", "Release", "-r", "win-x64", "--nologo")
    Sync-ReleaseRuntimeAssetsV74023 -Root $repoRoot
}
catch {
    if ($state -eq "Baseline" -and $backupAgc -and [System.IO.File]::Exists($backupAgc)) {
        Copy-Item -LiteralPath $backupAgc -Destination $agcPath -Force
        Write-Host "[V74.0.23] Build failed; AgcExports.cs restored from backup."
    }
    throw
}
$releaseDll = [System.IO.Path]::Combine($repoRoot, "artifacts", "bin", "Release", "net10.0", "win-x64", "SharpEmu.dll")
if (-not [System.IO.File]::Exists($releaseDll)) { throw "[V74.0.23] Release SharpEmu.dll missing after build." }
$hostHashFinal = if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
if ($hostHashFinal -ne $hostHashBefore) { throw "[V74.0.23] HostMovieBridge hash changed during RUN_3." }
Write-Host "[V74.0.23] SUCCESS - large-array cache validation repair built."
Write-Host "[V74.0.23] Default behavior remains unchanged; only RUN_4 enables SHARPEMU_LARGE_ARRAY_CACHE_TRUST=1."
Write-Host "[V74.0.23] V74.0.21 Entry ABI preserved; guest-owned Bink policy preserved."
Write-Host "[V74.0.23] Next: RUN_4_DEMONS_LARGE_ARRAY_CACHE_TEST.cmd"
