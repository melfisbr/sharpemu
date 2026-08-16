param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$targets = @(
    @{
        Rel = 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
        Patch = 'patch\DirectExecutionBackend.cs'
    },
    @{
        Rel = 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
        Patch = 'patch\DirectExecutionBackend.GuestSampler.cs'
    }
)

$direct = Join-Path $root $targets[0].Rel
$sampler = Join-Path $root $targets[1].Rel
$directText = [IO.File]::ReadAllText($direct)
$samplerText = [IO.File]::ReadAllText($sampler)

$already =
    (Test-ContainsOrdinal -Text $samplerText -Pattern 'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT') -and
    -not (Test-ContainsOrdinal -Text $directText -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE')

if ($already) {
    Write-Host '[V73.11] Rollback/probe already installed; building current source.'
    Push-Location $root
    try {
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        $buildExit = $LASTEXITCODE
        if ($buildExit -ne 0) {
            throw ('SharpEmu.CLI build failed with exit code {0}.' -f $buildExit)
        }
    }
    finally {
        Pop-Location
    }
    Write-Host '[V73.11] SUCCESS (already installed)'
    Write-Host '[V73.11] Next: RUN_DEMONS_ENTRY_WAIT_DIAGNOSTIC_V73_11.cmd'
    return
}

$expectedDirect = '054C0C4FA74F3B2D3599DCA36F0CC7F374088093DCF1ACE337B179A638EA34CD'
$expectedSampler = 'DDB0C1FBDF353AE8922C73236FB83B186BDAC49750E47F3D814D6A0AD7495E75'
$actualDirect = (Get-FileHash -LiteralPath $direct -Algorithm SHA256).Hash
$actualSampler = (Get-FileHash -LiteralPath $sampler -Algorithm SHA256).Hash
if ($actualDirect -ne $expectedDirect -or $actualSampler -ne $expectedSampler) {
    throw (
        '[V73.11] APPLY ERROR: source changed after precheck. Direct={0}; Sampler={1}' -f
        $actualDirect,
        $actualSampler)
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $root ('.sharpemu-hotfix-backup\MainEntryWaitCounter_V73_11_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$changed = New-Object System.Collections.Generic.List[object]

try {
    foreach ($item in $targets) {
        $destination = Join-Path $root $item.Rel
        $backup = Join-Path $backupRoot $item.Rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup -Force
        Copy-Item `
            -LiteralPath (Join-Path $packageRoot $item.Patch) `
            -Destination $destination `
            -Force
        $changed.Add($item)
        Write-Host ('[V73.11] installed: {0}' -f $item.Rel)
    }

    $directAfter = [IO.File]::ReadAllText($direct)
    $samplerAfter = [IO.File]::ReadAllText($sampler)

    if (Test-ContainsOrdinal -Text $directAfter -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE') {
        throw '[V73.11] V73.10 usleep preference still present after install.'
    }

    foreach ($marker in @(
        'ulong R14,',
        'ulong R15);'
    )) {
        if (-not (Test-ContainsOrdinal -Text $directAfter -Pattern $marker)) {
            throw ('[V73.11] Direct context marker missing: {0}' -f $marker)
        }
    }

    foreach ($marker in @(
        'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
        '[V73.11][ENTRY_WAIT]',
        '[V73.11][ENTRY]',
        'thread=<entry-main>'
    )) {
        if (-not (Test-ContainsOrdinal -Text $samplerAfter -Pattern $marker)) {
            throw ('[V73.11] GuestSampler marker missing: {0}' -f $marker)
        }
    }

    Push-Location $root
    try {
        Write-Host '[V73.11] Building SharpEmu.CLI Debug win-x64...'
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

    Write-Host '[V73.11] SUCCESS'
    Write-Host ('[V73.11] Backup: {0}' -f $backupRoot)
    Write-Host '[V73.11] V73.10 usleep HLE preference removed.'
    Write-Host '[V73.11] Initial entry-thread wait counter/UI reachability probe installed.'
    Write-Host '[V73.11] Next: RUN_DEMONS_ENTRY_WAIT_DIAGNOSTIC_V73_11.cmd'
}
catch {
    foreach ($item in $changed) {
        $destination = Join-Path $root $item.Rel
        $backup = Join-Path $backupRoot $item.Rel
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Copy-Item -LiteralPath $backup -Destination $destination -Force
            Write-Host ('[V73.11] restored: {0}' -f $item.Rel)
        }
    }
    throw
}
