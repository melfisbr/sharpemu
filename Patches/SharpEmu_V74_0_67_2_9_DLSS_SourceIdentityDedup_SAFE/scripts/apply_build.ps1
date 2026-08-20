. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot
$patches = Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$bridge = Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b = Normalize-Lf ([IO.File]::ReadAllText($bridge))
$already =
    $b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')

$backup = $null
if (!$already) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_9_$stamp"
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    Copy-Item -LiteralPath $bridge `
        -Destination (Join-Path $backup 'VulkanUpscalerBridge.cs') `
        -Force

    try {
        & (Join-Path $PSScriptRoot 'patch_source.ps1')
    }
    catch {
        Write-Warning '[V74.0.67.2.9] Patch failed; restoring VulkanUpscalerBridge.cs.'
        Copy-Item `
            -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Destination $bridge `
            -Force
        throw
    }
}
else {
    Write-Host '[V74.0.67.2.9] Source already patched; build only.'
}

Stop-SharpEmuForBuild

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog = Join-Path $patches "SharpEmu_V74_0_67_2_9_DLSS_SOURCE_DEDUP_BUILD_$stamp.log"
$cli = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

Write-Host '[V74.0.67.2.9] Building accumulated SharpEmu Release win-x64...'
$oldPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $buildOutput = @(& dotnet build $cli -c Release -r win-x64 2>&1)
    $buildExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $oldPreference
}

$buildLines = @(
    foreach ($item in $buildOutput) {
        if ($null -eq $item) { continue }
        $text = $item.ToString()
        Write-Host $text
        $text
    }
)
$buildLines | Set-Content -LiteralPath $buildLog -Encoding UTF8

if ($buildExit -ne 0) {
    if (!$already -and $null -ne $backup) {
        Write-Warning '[V74.0.67.2.9] Host build failed; restoring VulkanUpscalerBridge.cs.'
        Copy-Item `
            -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Destination $bridge `
            -Force
    }
    throw "SharpEmu.CLI build failed: native exit $buildExit"
}

$releaseHost = Find-ReleaseHost -Repo $repo
if ($null -eq $releaseHost) {
    if (!$already -and $null -ne $backup) {
        Copy-Item `
            -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Destination $bridge `
            -Force
    }
    throw 'Release win-x64 SharpEmu.exe not found after build.'
}

Write-Host '[V74.0.67.2.9] APPLY + BUILD PASSED.'
Write-Host "[V74.0.67.2.9] BuildLog=$buildLog"
Write-Host "[V74.0.67.2.9] Host=$($releaseHost.FullName)"
if ($null -ne $backup) {
    Write-Host "[V74.0.67.2.9] Backup=$backup"
}
