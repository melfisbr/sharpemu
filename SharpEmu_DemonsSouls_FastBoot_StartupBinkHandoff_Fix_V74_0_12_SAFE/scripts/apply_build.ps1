param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$presenter=Get-PresenterPath $root
$hostMovie=Get-HostMovieBridgePathV74012 $root
$presenterPayload=Get-PresenterPayloadV74011

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot=[System.IO.Path]::Combine(
    $root,".sharpemu-hotfix-backup","FastBootStartupBinkHandoff_V74_0_12_$stamp")
[System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null

$backupPresenter=[System.IO.Path]::Combine($backupRoot,"VulkanVideoPresenter.cs")
$backupHostMovie=[System.IO.Path]::Combine($backupRoot,"HostMovieBridge.cs")
Copy-Item -LiteralPath $presenter -Destination $backupPresenter -Force
Copy-Item -LiteralPath $hostMovie -Destination $backupHostMovie -Force

try{
    $currentPresenter=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
    if($currentPresenter-ne"B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245"){
        Copy-Item -LiteralPath $presenterPayload -Destination $presenter -Force
    }

    Install-StartupBinkHandoffV74012 -Path $hostMovie

    $presenterFinal=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
    if($presenterFinal-ne"B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245"){
        throw "[V74.0.12] Presenter install SHA mismatch: $presenterFinal"
    }

    $hostText=[System.IO.File]::ReadAllText($hostMovie)
    if(-not $hostText.Contains("SHARPEMU_V74_0_12_STARTUP_BINK_COMPLETION_HANDOFF") -or
       -not $hostText.Contains("bink2.startup_completion_shim")){
        throw "[V74.0.12] HostMovieBridge completion handoff verification failed."
    }

    Write-Host "[V74.0.12] Startup Bink completion handoff installed."
    Write-Host "[V74.0.12] ps_studios_logo + logo_intro: host playback completes before guest sees one-frame completion header."
    Write-Host "[V74.0.12] logo_intro_loop remains guest-owned."
    Write-Host "[V74.0.12] Completed host movie now releases exclusive fallback immediately."
    Write-Host "[V74.0.12] Presenter can start one-shot fallback directly from render tick."
    Write-Host "[V74.0.12] Backup: $backupRoot"

    Write-Host "[V74.0.12] Building Debug win-x64..."
    Invoke-DotNetChecked $root @(
        "build",
        "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug","-r","win-x64","--nologo")
}
catch{
    Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
    Copy-Item -LiteralPath $backupHostMovie -Destination $hostMovie -Force
    Write-Host "[V74.0.12] Apply/build failed; both sources restored."
    throw
}

Write-Host "[V74.0.12] FINAL presenter_sha=$((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.12] FINAL native_lane=True"
Write-Host "[V74.0.12] FINAL fastboot_trace_policy=True"
Write-Host "[V74.0.12] FINAL startup_completion_handoff=True"
Write-Host "[V74.0.12] FINAL completed_movie_visual_release=True"
Write-Host "[V74.0.12] SUCCESS"
Write-Host "[V74.0.12] Next: RUN_DEMONS_FASTBOOT_HANDOFF_V74_0_12.cmd"
