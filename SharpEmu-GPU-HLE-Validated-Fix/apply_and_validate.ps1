param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupRoot = Join-Path $RepositoryRoot ("artifacts\backup-gpu-hle-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))

$relativeFiles = @(
    'src\SharpEmu.Libs\Kernel\KernelPthreadCompatExports.cs',
    'src\SharpEmu.Libs\Kernel\KernelPthreadLibcStartupExports.cs',
    'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs',
    'src\SharpEmu.Libs\Agc\AgcExports.cs'
)

Write-Host "Repository: $RepositoryRoot"
Write-Host "Backup:     $backupRoot"

foreach ($relative in $relativeFiles) {
    $source = Join-Path $packageRoot $relative
    $destination = Join-Path $RepositoryRoot $relative
    $backup = Join-Path $backupRoot $relative

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Package file missing: $source"
    }

    if (Test-Path -LiteralPath $destination) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup -Force
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Host "Applied: $relative"
}

Push-Location $RepositoryRoot
try {
    dotnet build

    if (-not $SkipTests) {
        dotnet test tests\SharpEmu.Libs.Tests\SharpEmu.Libs.Tests.csproj --no-restore
        dotnet test tests\SharpEmu.ShaderCompiler.Tests\SharpEmu.ShaderCompiler.Tests.csproj --no-restore
    }
}
finally {
    Pop-Location
}

Write-Host 'Patch applied and validation commands completed.'
Write-Host "Original files are in: $backupRoot"
