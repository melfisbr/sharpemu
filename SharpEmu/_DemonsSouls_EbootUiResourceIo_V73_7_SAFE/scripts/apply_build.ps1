param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$targets = @(
    @{
        Rel='src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
        Patch='patch\KernelMemoryCompatExports.cs'
        Marker='SHARPEMU_DEMONSSOULS_UI_READ_SERIALIZATION_V73_7'
    },
    @{
        Rel='src\SharpEmu.Libs\Ampr\AmprExports.cs'
        Patch='patch\AmprExports.cs'
        Marker='SHARPEMU_DEMONSSOULS_UI_AMPR_READ_FILTER_V73_7'
    }
)

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $root ('.sharpemu-hotfix-backup\EbootUiResourceIo_V73_7_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$changed = New-Object System.Collections.Generic.List[object]

try {
    foreach ($item in $targets) {
        $destination = Join-Path $root $item.Rel
        $current = [IO.File]::ReadAllText($destination)
        if (Test-ContainsOrdinal -Text $current -Pattern $item.Marker) {
            Write-Host ('[V73.7] already installed: {0}' -f $item.Rel)
            continue
        }

        $backup = Join-Path $backupRoot $item.Rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup -Force
        Copy-Item -LiteralPath (Join-Path $pkg $item.Patch) -Destination $destination -Force
        $changed.Add($item)
        Write-Host ('[V73.7] installed: {0}' -f $item.Rel)
    }

    Push-Location $root
    try {
        Write-Host '[V73.7] Building SharpEmu.CLI Debug win-x64...'
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { throw ('SharpEmu.CLI build failed with exit code {0}.' -f $exit) }
    }
    finally { Pop-Location }

    Write-Host '[V73.7] SUCCESS'
    Write-Host ('[V73.7] Backup: {0}' -f $backupRoot)
    Write-Host '[V73.7] _read/sceKernelRead is now serialized against close(fd).'
    Write-Host '[V73.7] APR/AMPR ABI semantics were preserved.'
    Write-Host '[V73.7] Next: RUN_DEMONS_UI_RESOURCE_IO_V73_7.cmd'
}
catch {
    foreach ($item in $changed) {
        $destination = Join-Path $root $item.Rel
        $backup = Join-Path $backupRoot $item.Rel
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Copy-Item -LiteralPath $backup -Destination $destination -Force
            Write-Host ('[V73.7] restored: {0}' -f $item.Rel)
        }
    }
    throw
}
