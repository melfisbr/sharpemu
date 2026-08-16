param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$presenter=Get-PresenterPath $root
$payload=Get-PresenterPayloadV74011
$current=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$installedSha="B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41"

$backupRoot=$null
$backupPresenter=$null

if($current-ne$installedSha){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine(
        $root,".sharpemu-hotfix-backup","NaturalBinkDescriptorlessFallback_V74_0_11_$stamp")
    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null

    $backupPresenter=[System.IO.Path]::Combine(
        $backupRoot,"VulkanVideoPresenter.cs")
    Copy-Item -LiteralPath $presenter -Destination $backupPresenter -Force

    try{
        Copy-Item -LiteralPath $payload -Destination $presenter -Force

        $sha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
        if($sha-ne$installedSha){
            throw "[V74.0.11] Installed presenter SHA mismatch: $sha"
        }

        $text=[System.IO.File]::ReadAllText($presenter)
        foreach($marker in @(
            "SHARPEMU_V74_0_11_NATURAL_BINK_DESCRIPTORLESS_DIRECT_FALLBACK",
            "SHARPEMU_V74_0_11_NATURAL_BINK_RENDER_TICK_PUMP",
            "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET",
            "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE"
        )){
            if(-not $text.Contains($marker)){
                throw "[V74.0.11] Installed marker missing: $marker"
            }
        }

        Write-Host "[V74.0.11] Installed natural-Bink descriptorless direct fallback."
        Write-Host "[V74.0.11] Fallback activates only when host Bink is active and guest texture count is zero."
        Write-Host "[V74.0.11] Presenter tick now pumps natural Bink independently of guest draw/compute cadence."
        Write-Host "[V74.0.11] Real guest Y/UV pair immediately releases the direct fallback."
        Write-Host "[V74.0.11] V74.0.10 native lane preserved."
        Write-Host "[V74.0.11] Backup: $backupRoot"
    } catch {
        if($null-ne$backupPresenter -and [System.IO.File]::Exists($backupPresenter)){
            Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
        }
        Write-Host "[V74.0.11] Apply failed; presenter restored."
        throw
    }
} else {
    Write-Host "[V74.0.11] Presenter already installed; building only."
}

try{
    Write-Host "[V74.0.11] Building Debug win-x64..."
    Invoke-DotNetChecked $root @(
        "build",
        "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug","-r","win-x64","--nologo")
} catch {
    if($null-ne$backupPresenter -and [System.IO.File]::Exists($backupPresenter)){
        Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
    }
    Write-Host "[V74.0.11] Build failed; presenter restored."
    throw
}

$final=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.11] FINAL presenter_sha=$final"
Write-Host "[V74.0.11] FINAL native_lane=True"
Write-Host "[V74.0.11] FINAL descriptorless_direct_fallback=True"
Write-Host "[V74.0.11] FINAL render_tick_bink_pump=True"
Write-Host "[V74.0.11] FINAL yuv_release_path=True"
Write-Host "[V74.0.11] SUCCESS"
Write-Host "[V74.0.11] Next: RUN_DEMONS_NATURAL_BINK_FALLBACK_V74_0_11.cmd"
