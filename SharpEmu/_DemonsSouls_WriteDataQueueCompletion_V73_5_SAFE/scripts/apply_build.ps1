param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$targets = @(
    @{
        Rel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
        Patch = 'patch\AgcExports.cs'
        Marker = 'requiresGpuBufferReadback: false'
    },
    @{
        Rel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
        Patch = 'patch\VulkanVideoPresenter.cs'
        Marker = 'RequiresQueueCompletionOnly'
    },
    @{
        Rel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs'
        Patch = 'patch\VulkanGuestGpuBackend.cs'
        Marker = 'SubmitOrderedGuestActionAfterQueueCompletion'
    },
    @{
        Rel = 'src\SharpEmu.Libs\Gpu\IGuestGpuBackend.cs'
        Patch = 'patch\IGuestGpuBackend.cs'
        Marker = 'SubmitOrderedGuestActionAfterQueueCompletion'
    }
)

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $root (
    '.sharpemu-hotfix-backup\WriteDataQueueCompletion_V73_5_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$changed = New-Object System.Collections.Generic.List[object]

try {
    foreach ($item in $targets) {
        $destination = Join-Path $root $item.Rel
        $currentText = [IO.File]::ReadAllText($destination)

        if (Test-ContainsOrdinal -Text $currentText -Pattern $item.Marker) {
            Write-Host ('[V73.5] already installed: {0}' -f $item.Rel)
            continue
        }

        $backupPath = Join-Path $backupRoot $item.Rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) |
            Out-Null
        Copy-Item -LiteralPath $destination -Destination $backupPath -Force

        $patchPath = Join-Path $packageRoot $item.Patch
        Copy-Item -LiteralPath $patchPath -Destination $destination -Force
        $changed.Add($item)

        Write-Host ('[V73.5] installed: {0}' -f $item.Rel)
    }

    foreach ($item in $targets) {
        $text = [IO.File]::ReadAllText((Join-Path $root $item.Rel))
        if (-not (Test-ContainsOrdinal -Text $text -Pattern $item.Marker)) {
            throw ('[V73.5] post-install marker missing: {0}' -f $item.Marker)
        }
    }

    Push-Location $root
    try {
        Write-Host '[V73.5] Building SharpEmu.CLI Debug win-x64...'
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' `
            -c Debug `
            -r win-x64 `
            --nologo
        $buildExit = $LASTEXITCODE

        if ($buildExit -ne 0) {
            throw ('SharpEmu.CLI build failed with exit code {0}.' -f $buildExit)
        }
    }
    finally {
        Pop-Location
    }

    Write-Host '[V73.5] SUCCESS'
    Write-Host ('[V73.5] Backup: {0}' -f $backupRoot)
    Write-Host '[V73.5] Queue completion is preserved for WRITE_DATA.'
    Write-Host '[V73.5] Dirty storage-buffer GPU->CPU readback is no longer a prerequisite for WRITE_DATA.'
    Write-Host '[V73.5] Next: RUN_DEMONS_WRITEDATA_PRODUCER_V73_5.cmd'
}
catch {
    foreach ($item in $changed) {
        $destination = Join-Path $root $item.Rel
        $backupPath = Join-Path $backupRoot $item.Rel

        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Copy-Item -LiteralPath $backupPath -Destination $destination -Force
            Write-Host ('[V73.5] restored: {0}' -f $item.Rel)
        }
    }

    throw
}
