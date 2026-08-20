. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot
$backupRoot = Join-Path $repo '.sharpemu-hotfix-backup'

$backup = @(
    Get-ChildItem -LiteralPath $backupRoot -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like 'DemonPostAttractFenceV1_1_12_*'
    } |
    Sort-Object LastWriteTime -Descending
) | Select-Object -First 1

if ($null -eq $backup) {
    throw "$script:Tag No V1.1.12 backup found."
}

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$radPath =
    Find-UniqueSourceFile $repo 'RadBinkEmbeddedHostApiV724323171.cs'

Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'BinkDemonSoulsIntroAudioV7243227.cs') `
    -Destination $introPath -Force

Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'RadBinkEmbeddedHostApiV724323171.cs') `
    -Destination $radPath -Force

$nativeTargets = [ordered]@{
    Debug =
        Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
    Release =
        Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
}

foreach ($name in $nativeTargets.Keys) {
    $saved =
        Join-Path $backup.FullName (
            $name +
            '_SharpEmu.BinkNative.dll')

    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        $target = $nativeTargets[$name]
        New-Item -ItemType Directory -Force -Path (
            Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $saved -Destination $target -Force
        Write-Step "NativeDllRestored=$target"
    }
}

Invoke-GuiBuild $repo

Write-Step "RollbackSource=$($backup.FullName)"
Write-Step "ROLLBACK PASSED."
