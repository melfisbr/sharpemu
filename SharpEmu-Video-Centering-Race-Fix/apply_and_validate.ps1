param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path $RepositoryRoot).Path
$relative = "src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs"
$source = Join-Path $packageRoot $relative
$destination = Join-Path $repo $relative
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backup = Join-Path $repo "artifacts\backup-video-centering-$stamp\$relative"

if (-not (Test-Path -LiteralPath $source)) {
    throw "Arquivo do pacote nao encontrado: $source"
}

if (-not (Test-Path -LiteralPath $destination)) {
    throw "Arquivo do repositorio nao encontrado: $destination"
}

New-Item -ItemType Directory -Force `
    -Path (Split-Path -Parent $backup) | Out-Null

Copy-Item -LiteralPath $destination -Destination $backup -Force
Copy-Item -LiteralPath $source -Destination $destination -Force

Write-Host "Aplicado: $relative"
Write-Host "Backup:   $backup"

$sourceCheck = Select-String `
    -LiteralPath $destination `
    -SimpleMatch "WaitForGuestSubmissionCompletion"

if (-not $sourceCheck) {
    throw "A verificacao da correcao falhou."
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$cli = Join-Path $repo "src\SharpEmu.CLI\SharpEmu.CLI.csproj"

Write-Host ""
Write-Host "Reconstruindo o runtime..."
dotnet build $cli -c Debug -r win-x64 --no-incremental
if ($LASTEXITCODE -ne 0) {
    throw "Falha no build do CLI."
}

$libsTests = Join-Path $repo `
    "tests\SharpEmu.Libs.Tests\SharpEmu.Libs.Tests.csproj"

if (Test-Path -LiteralPath $libsTests) {
    Write-Host ""
    Write-Host "Executando SharpEmu.Libs.Tests..."
    dotnet test $libsTests -c Debug --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Falha nos testes de Libs."
    }
}

Write-Host ""
Write-Host "Correcao de sincronizacao do flip aplicada."
Write-Host "Remova SHARPEMU_LOG_AGC antes de testar:"
Write-Host "Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue"
