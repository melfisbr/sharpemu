param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$presenter = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$source = [IO.File]::ReadAllText($presenter)

$bugPattern =
    'new VulkanOrderedGuestAction\(\s*action,\s*debugName,\s*requiresGpuToCpuVisibility\)'
$bugMatch = [regex]::Match(
    $source,
    $bugPattern,
    [Text.RegularExpressions.RegexOptions]::Singleline)

$fixedMarker = 'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)'

if (-not $bugMatch.Success) {
    if (Test-ContainsOrdinal -Text $source -Pattern $fixedMarker) {
        Write-Host '[V73.3] Correct visibility binding is already installed; building current source.'
    }
    else {
        throw '[V73.3] APPLY ERROR: audited constructor disappeared after precheck.'
    }

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

    Write-Host '[V73.3] SUCCESS (already fixed)'
    Write-Host '[V73.3] Next: RUN_DEMONS_DIAGNOSTIC_V73_3.cmd'
    return
}

$baselineHash = '534EB79448DF504500D1B018DA98714778FB13D06EC2FF887AC9544C2A1A6364'
$currentHash = (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
if ($currentHash -ne $baselineHash) {
    throw (
        '[V73.3] APPLY ERROR: presenter changed after precheck. Expected {0}; actual {1}.' -f
        $baselineHash,
        $currentHash)
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $root ('.sharpemu-hotfix-backup\OrderedVisibility_V73_3_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir 'VulkanVideoPresenter.cs'
Copy-Item -LiteralPath $presenter -Destination $backup -Force

try {
    $lineBreak = "`n"
    if ($source.IndexOf("`r`n", [StringComparison]::Ordinal) -ge 0) {
        $lineBreak = "`r`n"
    }

    $replacement =
        'new VulkanOrderedGuestAction(' + $lineBreak +
        '                        action,' + $lineBreak +
        '                        debugName,' + $lineBreak +
        '                        RequireGlobalVisibility: false,' + $lineBreak +
        '                        RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)'

    $patched =
        $source.Substring(0, $bugMatch.Index) +
        $replacement +
        $source.Substring($bugMatch.Index + $bugMatch.Length)

    if ($patched -eq $source) {
        throw '[V73.3] Source transformation produced no change.'
    }

    if (-not (Test-ContainsOrdinal -Text $patched -Pattern 'RequireGlobalVisibility: false,') -or
        -not (Test-ContainsOrdinal -Text $patched -Pattern $fixedMarker)) {
        throw '[V73.3] Post-patch semantic validation failed.'
    }

    [IO.File]::WriteAllText(
        $presenter,
        $patched,
        [Text.UTF8Encoding]::new($false))

    Write-Host '[V73.3] Corrected VulkanOrderedGuestAction named visibility binding.'

    Push-Location $root
    try {
        Write-Host '[V73.3] Building SharpEmu.CLI Debug win-x64...'
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

    $final = [IO.File]::ReadAllText($presenter)
    if ([regex]::IsMatch(
            $final,
            $bugPattern,
            [Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw '[V73.3] Build passed but buggy positional constructor remains.'
    }

    if (-not (Test-ContainsOrdinal -Text $final -Pattern $fixedMarker)) {
        throw '[V73.3] Build passed but fixed visibility marker is missing.'
    }

    Write-Host '[V73.3] SUCCESS'
    Write-Host ('[V73.3] Backup: {0}' -f $backupDir)
    Write-Host ('[V73.3] Presenter_SHA256={0}' -f (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)
    Write-Host '[V73.3] Next: RUN_DEMONS_DIAGNOSTIC_V73_3.cmd'
}
catch {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        Copy-Item -LiteralPath $backup -Destination $presenter -Force
        Write-Host '[V73.3] VulkanVideoPresenter.cs restored.'
    }

    throw
}
