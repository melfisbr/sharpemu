param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot

& (Join-Path $PSScriptRoot "precheck.ps1") `
    -RepositoryRoot $root

$presenter=Get-PresenterPath $root
$payload=Get-PayloadPath

$currentSha=(
    Get-FileHash -LiteralPath $presenter -Algorithm SHA256
).Hash.ToUpperInvariant()

$installedSha="1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28"

$backupRoot=$null
$backupPresenter=$null

if($currentSha-ne$installedSha){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"

    $backupRoot=[System.IO.Path]::Combine(
        $root,
        ".sharpemu-hotfix-backup",
        "SampledGuestImageResidency_V74_0_7_$stamp")

    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null

    $backupPresenter=[System.IO.Path]::Combine(
        $backupRoot,
        "VulkanVideoPresenter.cs")

    Copy-Item -LiteralPath $presenter -Destination $backupPresenter -Force

    try{
        Copy-Item -LiteralPath $payload -Destination $presenter -Force

        $installed=(
            Get-FileHash -LiteralPath $presenter -Algorithm SHA256
        ).Hash.ToUpperInvariant()

        if($installed-ne$installedSha){
            throw "[V74.0.7.1] Payload copy verification failed: $installed"
        }

        $text=[System.IO.File]::ReadAllText($presenter)

        foreach($marker in @(
            "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE",
            "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET",
            "SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE",
            "SHARPEMU_V74_0_7_1_INVALIDATE_API_REPAIR",
            "TrimSampledGuestImagesToBudgetV7407",
            "resources.Textures[index] = resolvedTexture;"
        )){
            if(-not $text.Contains($marker)){
                throw "[V74.0.7.1] Installed source marker missing: $marker"
            }
        }

        Write-Host "[V74.0.7.1] Installed exact audited presenter payload."
        Write-Host "[V74.0.7.1] Sampled-only GuestImage residency is byte-budgeted (512 MiB default)."
        Write-Host "[V74.0.7.1] Real RT/storage/display images are promoted out of the eviction class."
        Write-Host "[V74.0.7.1] Swapchain cached-texture staging retires on the owning frame fence."
        Write-Host "[V74.0.7.1] Correct cache invalidation API: InvalidateSampledTextureCacheForGuestAddressV56."
        Write-Host "[V74.0.7.1] V74.0.6.3 compute texture restore preserved."
        Write-Host "[V74.0.7.1] Backup: $backupRoot"
    } catch {
        if($null-ne$backupPresenter -and
           [System.IO.File]::Exists($backupPresenter)){
            Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
        }

        Write-Host "[V74.0.7.1] Apply failed; VulkanVideoPresenter.cs restored."
        throw
    }
} else {
    Write-Host "[V74.0.7.1] Source already installed; building only."
}

try{
    Write-Host "[V74.0.7.1] Building Debug win-x64..."

    Invoke-DotNetChecked $root @(
        "build",
        "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug",
        "-r","win-x64",
        "--nologo")
} catch {
    if($null-ne$backupPresenter -and
       [System.IO.File]::Exists($backupPresenter)){
        Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
    }

    Write-Host "[V74.0.7.1] Build failed; VulkanVideoPresenter.cs restored."
    throw
}

$finalSha=(
    Get-FileHash -LiteralPath $presenter -Algorithm SHA256
).Hash.ToUpperInvariant()

Write-Host "[V74.0.7.1] FINAL presenter_sha=$finalSha"
Write-Host "[V74.0.7.1] FINAL compute_restore=True"
Write-Host "[V74.0.7.1] FINAL sampled_guest_image_budget=True"
Write-Host "[V74.0.7.1] FINAL swapchain_staging_retire=True"
Write-Host "[V74.0.7.1] FINAL invalidate_api_repair=True"
Write-Host "[V74.0.7.1] SUCCESS"
Write-Host "[V74.0.7.1] Next: RUN_DEMONS_RESIDENCY_V74_0_7_1.cmd"
