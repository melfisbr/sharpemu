param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$kernel = Join-Path $root 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$current = [IO.File]::ReadAllText($kernel)

if (Test-ContainsOrdinal -Text $current -Pattern 'SHARPEMU_DEMONSSOULS_UI_READ_SERIALIZATION_V73_7_1') {
    Write-Host '[V73.7.1] Kernel read serialization already installed; building current source.'
    Push-Location $root
    try {
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { throw ('SharpEmu.CLI build failed with exit code {0}.' -f $exit) }
    }
    finally { Pop-Location }

    Write-Host '[V73.7.1] SUCCESS (already installed)'
    Write-Host '[V73.7.1] Next: RUN_DEMONS_UI_RESOURCE_IO_V73_7_1.cmd'
    return
}

$expected = '61D151DF2DDD8E9B1E7AF9451F1BDE3A7D109DB0B92F37F04D5BB60B4AD74103'
$actual = (Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash
if ($actual -ne $expected) {
    throw ('[V73.7.1] APPLY ERROR: Kernel source changed after precheck. expected={0} actual={1}' -f $expected,$actual)
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $root ('.sharpemu-hotfix-backup\EbootUiResourceIo_V73_7_1_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$backup = Join-Path $backupRoot 'KernelMemoryCompatExports.cs'
Copy-Item -LiteralPath $kernel -Destination $backup -Force

try {
    Copy-Item `
        -LiteralPath (Join-Path $pkg 'patch\KernelMemoryCompatExports.cs') `
        -Destination $kernel `
        -Force

    $patched = [IO.File]::ReadAllText($kernel)
    foreach ($marker in @(
        'SHARPEMU_TITLE_SCOPED_COMPAT_V73_0_13',
        'SHARPEMU_DEMONSSOULS_UI_READ_SERIALIZATION_V73_7_1',
        'Monitor.Enter(stream);',
        'Monitor.Exit(stream);',
        'catch (ObjectDisposedException ex)'
    )) {
        if (-not (Test-ContainsOrdinal -Text $patched -Pattern $marker)) {
            throw ('[V73.7.1] post-install marker missing: {0}' -f $marker)
        }
    }

    Push-Location $root
    try {
        Write-Host '[V73.7.1] Building SharpEmu.CLI Debug win-x64...'
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { throw ('SharpEmu.CLI build failed with exit code {0}.' -f $exit) }
    }
    finally { Pop-Location }

    Write-Host '[V73.7.1] SUCCESS'
    Write-Host ('[V73.7.1] Backup: {0}' -f $backupRoot)
    Write-Host '[V73.7.1] _read/read/sceKernelRead is serialized against close(fd).'
    Write-Host '[V73.7.1] V73.0.13.1 title isolation remains present.'
    Write-Host '[V73.7.1] Next: RUN_DEMONS_UI_RESOURCE_IO_V73_7_1.cmd'
}
catch {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        Copy-Item -LiteralPath $backup -Destination $kernel -Force
        Write-Host '[V73.7.1] KernelMemoryCompatExports.cs restored.'
    }
    throw
}
