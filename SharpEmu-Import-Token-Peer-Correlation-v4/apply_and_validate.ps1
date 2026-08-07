param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path $RepositoryRoot).Path
$relative = "src\SharpEmu.Core\Loader\ImportSymbolProvenance.cs"
$source = Join-Path $packageRoot $relative
$destination = Join-Path $repo $relative
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backup = Join-Path $repo "artifacts\backup-import-peer-v4-$stamp\$relative"

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
    "using SharpEmu.HLE;",
    "token_peer_nids=",
    "known_token_peers=",
    "peer_names='"
)
foreach ($token in $tokens) {
    if (-not (Select-String -LiteralPath $destination -SimpleMatch $token)) {
        throw "Verificacao falhou: $token"
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$cli = Join-Path $repo "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
Write-Host "Compilando runtime completo..."
dotnet build $cli -c Debug -r win-x64 --no-incremental
if ($LASTEXITCODE -ne 0) {
    throw "Falha no build do CLI."
}

Write-Host ""
Write-Host "Correlacao de imports por token aplicada."
Write-Host "Backup: $backup"
