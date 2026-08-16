param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot

& (Join-Path $PSScriptRoot "precheck.ps1") `
    -RepositoryRoot $root

$presenter=Get-PresenterPath $root
$payload=Get-PayloadPath

$currentSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$installedSha="0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"

$backupRoot=$null
$backupPresenter=$null

if($currentSha-ne$installedSha){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine(
        $root,".sharpemu-hotfix-backup","StandaloneTextureBudget_V74_0_8_$stamp")

    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
    $backupPresenter=[System.IO.Path]::Combine($backupRoot,"VulkanVideoPresenter.cs")
    Copy-Item -LiteralPath $presenter -Destination $backupPresenter -Force

    try{
        Copy-Item -LiteralPath $payload -Destination $presenter -Force

        $installed=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
        if($installed-ne$installedSha){
            throw "[V74.0.8.2] Payload copy verification failed: $installed"
        }

        $text=[System.IO.File]::ReadAllText($presenter)
        foreach($marker in @(
            "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET",
            "SHARPEMU_V74_0_8_TEXTURE_RESOURCE_RESIDENCY",
            "TrimStandaloneTextureCacheToBudgetV7408",
            "TraceResidencyPressureV7408",
            "SHARPEMU_V74_0_8_1_FULL_RUNTIME_MEMORY_TRUTH",
            "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET",
            "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE"
        )){
            if(-not $text.Contains($marker)){
                throw "[V74.0.8.2] Installed marker missing: $marker"
            }
        }

        Write-Host "[V74.0.8.2] Installed exact audited presenter payload."
        Write-Host "[V74.0.8.2] Standalone _textureCache is byte-budgeted: 768 MiB default, trim target 576 MiB."
        Write-Host "[V74.0.8.2] Cached texture VkImage memory size is tracked from vkGetImageMemoryRequirements."
        Write-Host "[V74.0.8.2] LRU-like cache retirement uses existing submission timeline."
        Write-Host "[V74.0.8.2] Comprehensive runtime-truth source remains installed; diagnostic finalizer repaired for Windows PowerShell 5.1."
        Write-Host "[V74.0.8.2] V74.0.7.1 residency/staging and V74.0.6.3 compute fixes preserved."
        Write-Host "[V74.0.8.2] Backup: $backupRoot"
    } catch {
        if($null-ne$backupPresenter -and [System.IO.File]::Exists($backupPresenter)){
            Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
        }
        Write-Host "[V74.0.8.2] Apply failed; VulkanVideoPresenter.cs restored."
        throw
    }
} else {
    Write-Host "[V74.0.8.2] Source already installed; building only."
}

try{
    Write-Host "[V74.0.8.2] Building Debug win-x64..."
    Invoke-DotNetChecked $root @(
        "build",
        "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug",
        "-r","win-x64",
        "--nologo")
} catch {
    if($null-ne$backupPresenter -and [System.IO.File]::Exists($backupPresenter)){
        Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
    }
    Write-Host "[V74.0.8.2] Build failed; VulkanVideoPresenter.cs restored."
    throw
}

$finalSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.8.2] FINAL presenter_sha=$finalSha"
Write-Host "[V74.0.8.2] FINAL compute_restore=True"
Write-Host "[V74.0.8.2] FINAL sampled_guest_image_budget=True"
Write-Host "[V74.0.8.2] FINAL standalone_texture_byte_budget=True"
Write-Host "[V74.0.8.2] FINAL residency_telemetry=True"
Write-Host "[V74.0.8.2] FINAL full_runtime_truth=True"
Write-Host "[V74.0.8.2] FINAL diagnostic_finalize_repair=True"
Write-Host "[V74.0.8.2] SUCCESS"
Write-Host "[V74.0.8.2] Next: RUN_DEMONS_TEXTURE_BUDGET_V74_0_8_2.cmd"
