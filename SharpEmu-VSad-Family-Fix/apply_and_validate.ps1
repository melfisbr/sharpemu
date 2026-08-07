param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path $RepositoryRoot).Path
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backup = Join-Path $repo "artifacts\backup-vsad-$stamp"

$files = @(
    "src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs",
    "src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.Alu.cs"
)

New-Item -ItemType Directory -Force -Path $backup | Out-Null

foreach ($relative in $files) {
    $source = Join-Path $packageRoot $relative
    $destination = Join-Path $repo $relative
    if (-not (Test-Path $source)) {
        throw "Arquivo do pacote não encontrado: $source"
    }
    if (-not (Test-Path $destination)) {
        throw "Arquivo do repositório não encontrado: $destination"
    }

    $backupFile = Join-Path $backup $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backupFile -Force
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Host "Aplicado: $relative"
}

Write-Host ""
Write-Host "Backup: $backup"
Write-Host "Compilando ShaderCompiler..."
dotnet build (Join-Path $repo "src\SharpEmu.ShaderCompiler.Vulkan\SharpEmu.ShaderCompiler.Vulkan.csproj")
if ($LASTEXITCODE -ne 0) { throw "Falha no build Vulkan." }

dotnet build (Join-Path $repo "src\SharpEmu.ShaderCompiler.Metal\SharpEmu.ShaderCompiler.Metal.csproj")
if ($LASTEXITCODE -ne 0) { throw "Falha no build Metal." }

$testProjects = @(
    "tests\SharpEmu.ShaderCompiler.Tests\SharpEmu.ShaderCompiler.Tests.csproj",
    "tests\SharpEmu.ShaderCompiler.Metal.Tests\SharpEmu.ShaderCompiler.Metal.Tests.csproj"
)

foreach ($testRelative in $testProjects) {
    $testProject = Join-Path $repo $testRelative
    if (Test-Path $testProject) {
        Write-Host "Executando: $testRelative"
        dotnet test $testProject --no-restore
        if ($LASTEXITCODE -ne 0) { throw "Falha em $testRelative" }
    }
}

Write-Host ""
Write-Host "Correção VSAD aplicada e validada com sucesso."
