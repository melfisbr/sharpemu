param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot=Resolve-RepoRootV74025 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot
$agcPath=Get-AgcPathV74025 -Root $repoRoot
$hostMoviePath=Get-HostMoviePathV74025 -Root $repoRoot
$presenterPath=Get-PresenterPathV74025 -Root $repoRoot
$agcText=[System.IO.File]::ReadAllText($agcPath)
$state=Get-V25StateV74025 -Text $agcText
$hostHashBefore=if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
$presenterHashBefore=if ([System.IO.File]::Exists($presenterPath)) { (Get-FileHash -LiteralPath $presenterPath -Algorithm SHA256).Hash } else { "missing" }
$backupDirectory=$null
$backupAgc=$null
if ($state -eq "Baseline") {
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDirectory=[System.IO.Path]::Combine($repoRoot,".sharpemu-hotfix-backup","WriteDataPacketPosition_V74_0_25_$stamp")
    [System.IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    $backupAgc=[System.IO.Path]::Combine($backupDirectory,"AgcExports.cs")
    Copy-Item -LiteralPath $agcPath -Destination $backupAgc -Force
    try {
        $patchedText=Convert-AgcV74025 -Text $agcText
        $utf8NoBom=New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($agcPath,$patchedText,$utf8NoBom)
        $verifyText=[System.IO.File]::ReadAllText($agcPath)
        if ((Get-V25StateV74025 -Text $verifyText) -ne "Applied") { throw "[V74.0.25] Post-write AGC verification failed." }
        $hostHashAfter=if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
        $presenterHashAfter=if ([System.IO.File]::Exists($presenterPath)) { (Get-FileHash -LiteralPath $presenterPath -Algorithm SHA256).Hash } else { "missing" }
        if ($hostHashAfter -ne $hostHashBefore) { throw "[V74.0.25] HostMovieBridge changed unexpectedly." }
        if ($presenterHashAfter -ne $presenterHashBefore) { throw "[V74.0.25] VulkanVideoPresenter changed unexpectedly." }
        Write-Host "[V74.0.25] SOURCE PATCH APPLIED: opt-in WRITE_DATA packet-position scheduling installed."
        Write-Host "[V74.0.25] Default remains the accumulated queue-completion path; RUN_4 alone enables SHARPEMU_WRITE_DATA_PACKET_POSITION=1."
        Write-Host "[V74.0.25] Backup: $backupDirectory"
    } catch {
        if ($backupAgc -and [System.IO.File]::Exists($backupAgc)) { Copy-Item -LiteralPath $backupAgc -Destination $agcPath -Force }
        Write-Host "[V74.0.25] Apply failed; AgcExports.cs restored."
        throw
    }
} else { Write-Host "[V74.0.25] Source correction already installed; build verification only." }
try {
    Write-Host "[V74.0.25] Building Release win-x64..."
    Invoke-DotNetCheckedV74025 -Root $repoRoot -Arguments @("build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74025 -Root $repoRoot
} catch {
    if ($state -eq "Baseline" -and $backupAgc -and [System.IO.File]::Exists($backupAgc)) {
        Copy-Item -LiteralPath $backupAgc -Destination $agcPath -Force
        Write-Host "[V74.0.25] Build failed; AgcExports.cs restored from backup."
    }
    throw
}
$releaseDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if (-not [System.IO.File]::Exists($releaseDll)) { throw "[V74.0.25] Release SharpEmu.dll missing after build." }
$hostHashFinal=if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
$presenterHashFinal=if ([System.IO.File]::Exists($presenterPath)) { (Get-FileHash -LiteralPath $presenterPath -Algorithm SHA256).Hash } else { "missing" }
if ($hostHashFinal -ne $hostHashBefore) { throw "[V74.0.25] HostMovieBridge hash changed during RUN_3." }
if ($presenterHashFinal -ne $presenterHashBefore) { throw "[V74.0.25] VulkanVideoPresenter hash changed during RUN_3." }
Write-Host "[V74.0.25] SUCCESS - WRITE_DATA packet-position test path built."
Write-Host "[V74.0.25] Preserved: V74.0.21 Entry ABI, V74.0.15 single-flight, V74.0.23.1 sparse baseline, V74.0.24 fresh stale source."
Write-Host "[V74.0.25] No HostMovieBridge/boot-order/Presenter source was changed."
Write-Host "[V74.0.25] Next: RUN_4_DEMONS_WRITE_DATA_PACKET_POSITION_TEST.cmd"
