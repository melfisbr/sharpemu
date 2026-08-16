param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot = Resolve-RepoRootV740231 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot
$presenterPath = Get-PresenterPathV740231 -Root $repoRoot
$hostMoviePath = Get-HostMoviePathV740231 -Root $repoRoot
$presenterText = [System.IO.File]::ReadAllText($presenterPath)
$state = Get-V231StateV740231 -Text $presenterText
$hostHashBefore = if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
$backupDirectory = $null
$backupPresenter = $null
if ($state -eq "Baseline") {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDirectory = [System.IO.Path]::Combine($repoRoot, ".sharpemu-hotfix-backup", "LargeArraySparseBaseline_V74_0_23_1_$stamp")
    [System.IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    $backupPresenter = [System.IO.Path]::Combine($backupDirectory, "VulkanVideoPresenter.cs")
    Copy-Item -LiteralPath $presenterPath -Destination $backupPresenter -Force
    try {
        $patchedText = Convert-PresenterV740231 -Text $presenterText
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($presenterPath, $patchedText, $utf8NoBom)
        $verifyText = [System.IO.File]::ReadAllText($presenterPath)
        if ((Get-V231StateV740231 -Text $verifyText) -ne "Applied") {
            throw "[V74.0.23.1] Post-write Presenter verification failed."
        }
        $hostHashAfter = if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
        if ($hostHashAfter -ne $hostHashBefore) { throw "[V74.0.23.1] HostMovieBridge changed unexpectedly." }
        Write-Host "[V74.0.23.1] SOURCE PATCH APPLIED: large-array sparse baseline support installed in VulkanVideoPresenter.cs."
        Write-Host "[V74.0.23.1] Backup: $backupDirectory"
    }
    catch {
        if ($backupPresenter -and [System.IO.File]::Exists($backupPresenter)) {
            Copy-Item -LiteralPath $backupPresenter -Destination $presenterPath -Force
        }
        Write-Host "[V74.0.23.1] Apply failed; VulkanVideoPresenter.cs restored."
        throw
    }
}
else {
    Write-Host "[V74.0.23.1] Source correction already installed; build verification only."
}
try {
    Write-Host "[V74.0.23.1] Building Release win-x64..."
    Invoke-DotNetCheckedV740231 -Root $repoRoot -Arguments @("build", "src\SharpEmu.CLI\SharpEmu.CLI.csproj", "-c", "Release", "-r", "win-x64", "--nologo")
    Sync-ReleaseRuntimeAssetsV740231 -Root $repoRoot
}
catch {
    if ($state -eq "Baseline" -and $backupPresenter -and [System.IO.File]::Exists($backupPresenter)) {
        Copy-Item -LiteralPath $backupPresenter -Destination $presenterPath -Force
        Write-Host "[V74.0.23.1] Build failed; VulkanVideoPresenter.cs restored from backup."
    }
    throw
}
$releaseDll = [System.IO.Path]::Combine($repoRoot, "artifacts", "bin", "Release", "net10.0", "win-x64", "SharpEmu.dll")
if (-not [System.IO.File]::Exists($releaseDll)) { throw "[V74.0.23.1] Release SharpEmu.dll missing after build." }
$hostHashFinal = if ([System.IO.File]::Exists($hostMoviePath)) { (Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash } else { "missing" }
if ($hostHashFinal -ne $hostHashBefore) { throw "[V74.0.23.1] HostMovieBridge hash changed during RUN_3." }
Write-Host "[V74.0.23.1] SUCCESS - large-array sparse baseline repair built."
Write-Host "[V74.0.23.1] No AGC/HostMovieBridge/boot-order source was changed by this revision."
Write-Host "[V74.0.23.1] Next: RUN_4_DEMONS_LARGE_ARRAY_BASELINE_TEST.cmd"
