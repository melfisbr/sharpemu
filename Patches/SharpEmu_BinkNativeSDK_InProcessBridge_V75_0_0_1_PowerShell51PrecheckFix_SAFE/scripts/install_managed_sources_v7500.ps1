param(
    [Parameter(Mandatory=$true)]
    [string]$Repo,
    [Parameter(Mandatory=$true)]
    [string]$BackupRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$packageRoot = Get-PackageRoot
$mediaDir = Join-Path $Repo 'src\SharpEmu.Libs\Media'

foreach ($fileName in @(
    'BinkNativeSdkAbiV7500.cs',
    'RadBinkNativeSdkDecoderV7500.cs'
)) {
    $source = Join-Path (
        Join-Path $packageRoot 'source\managed') $fileName
    $target = Join-Path $mediaDir $fileName

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Copy-Item -LiteralPath $target -Destination (
            Join-Path $BackupRoot $fileName) -Force
    }

    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Step "ManagedSourceInstalled=$target"
}
