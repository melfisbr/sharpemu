param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path $RepositoryRoot).Path
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backupRoot = Join-Path $repo "artifacts\backup-import-decoder-v3-$stamp"

$files = @(
    "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs",
    "src\SharpEmu.Core\Loader\SelfLoader.cs",
    "src\SharpEmu.Core\Loader\ImportSymbolProvenance.cs",
    "src\SharpEmu.Core\Runtime\SharpEmuRuntime.cs"
)

foreach ($relative in $files) {
    $source = Join-Path $packageRoot $relative
    $destination = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Arquivo do pacote nao encontrado: $source"
    }

    if (Test-Path -LiteralPath $destination) {
        $backup = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Force `
            -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup -Force
    }

    New-Item -ItemType Directory -Force `
        -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Host "Aplicado: $relative"
}

$selfLoader = Join-Path $repo `
    "src\SharpEmu.Core\Loader\SelfLoader.cs"

$tokens = @(
    "value & 0x0FFF",
    "(value >> 32) & 0x0F",
    "(value >> 40) & 0x0F",
    "[LOADER] SCE import metadata:"
)

foreach ($token in $tokens) {
    if (-not (Select-String `
            -LiteralPath $selfLoader `
            -SimpleMatch $token)) {
        throw "Verificacao falhou: $token"
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$cli = Join-Path $repo "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
Write-Host ""
Write-Host "Compilando runtime completo..."
dotnet build $cli -c Debug -r win-x64 --no-incremental
if ($LASTEXITCODE -ne 0) {
    throw "Falha no build do CLI."
}

$tests = Join-Path $repo `
    "tests\SharpEmu.Libs.Tests\SharpEmu.Libs.Tests.csproj"
if (Test-Path -LiteralPath $tests) {
    Write-Host ""
    Write-Host "Executando SharpEmu.Libs.Tests..."
    dotnet test $tests -c Debug --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Falha nos testes de Libs."
    }
}

Write-Host ""
Write-Host "Decodificador SCE v3 aplicado."
Write-Host "Backup: $backupRoot"
