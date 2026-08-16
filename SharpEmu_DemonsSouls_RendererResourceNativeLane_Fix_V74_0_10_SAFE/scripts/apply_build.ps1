param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$native=Get-NativeWorkerPathV74010 $root
$payload=Get-PayloadNativeWorkerV74010
$current=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
$installedSha="F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38"

$backupRoot=$null
$backupNative=$null

if($current-ne$installedSha){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine(
        $root,".sharpemu-hotfix-backup","RendererResourceNativeLane_V74_0_10_$stamp")
    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
    $backupNative=[System.IO.Path]::Combine(
        $backupRoot,"DirectExecutionBackend.NativeWorker.cs")
    Copy-Item -LiteralPath $native -Destination $backupNative -Force

    try{
        Copy-Item -LiteralPath $payload -Destination $native -Force
        $sha=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
        if($sha-ne$installedSha){
            throw "[V74.0.10] Installed NativeWorker SHA mismatch: $sha"
        }
        Write-Host "[V74.0.10] Renderer/resource native lane installed."
        Write-Host "[V74.0.10] HighGraphics/Core.Res/Nexus capacity=8."
        Write-Host "[V74.0.10] Historical TBB capacity remains=2."
        Write-Host "[V74.0.10] No managed-inline fallback introduced."
        Write-Host "[V74.0.10] Backup: $backupRoot"
    } catch {
        if($null-ne$backupNative -and [System.IO.File]::Exists($backupNative)){
            Copy-Item -LiteralPath $backupNative -Destination $native -Force
        }
        Write-Host "[V74.0.10] Apply failed; NativeWorker restored."
        throw
    }
} else {
    Write-Host "[V74.0.10] Source already installed; building only."
}

try{
    Write-Host "[V74.0.10] Building Debug win-x64..."
    Invoke-DotNetChecked $root @(
        "build",
        "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug","-r","win-x64","--nologo")
} catch {
    if($null-ne$backupNative -and [System.IO.File]::Exists($backupNative)){
        Copy-Item -LiteralPath $backupNative -Destination $native -Force
    }
    Write-Host "[V74.0.10] Build failed; NativeWorker restored."
    throw
}

$final=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.10] FINAL native_worker_sha=$final"
Write-Host "[V74.0.10] FINAL renderer_resource_lane=True"
Write-Host "[V74.0.10] FINAL renderer_resource_limit=8"
Write-Host "[V74.0.10] FINAL tbb_limit=2"
Write-Host "[V74.0.10] FINAL no_managed_inline=True"
Write-Host "[V74.0.10] SUCCESS"
Write-Host "[V74.0.10] Next: RUN_DEMONS_NATIVE_LANE_TRUTH_V74_0_10.cmd"
