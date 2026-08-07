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
$backup = Join-Path $repo "artifacts\backup-flip-writer-$stamp\$relative"

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

$tokens = @(
    "work is VulkanOrderedGuestFlip flip",
    "_guestImageWorkSequences.TryGetValue(",
    "work is VulkanOrderedGuestFlipWait flipWait"
)
foreach ($token in $tokens) {
    if (-not (Select-String -LiteralPath $destination -SimpleMatch $token)) {
        throw "Token ausente apos aplicacao: $token"
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$cli = Join-Path $repo "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
dotnet build $cli -c Debug -r win-x64 --no-incremental
if ($LASTEXITCODE -ne 0) {
    throw "Falha no build do CLI."
}

$tests = Join-Path $repo `
    "tests\SharpEmu.Libs.Tests\SharpEmu.Libs.Tests.csproj"
if (Test-Path -LiteralPath $tests) {
    dotnet test $tests -c Debug --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Falha nos testes de Libs."
    }
}

Write-Host ""
Write-Host "Dependencia Flip -> writer aplicada."
Write-Host "Backup: $backup"
