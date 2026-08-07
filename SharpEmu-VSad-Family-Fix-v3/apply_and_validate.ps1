param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path $RepositoryRoot).Path
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backupRoot = Join-Path $repo "artifacts\backup-vsad-$stamp"

$relativeFiles = @(
    "src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs",
    "src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.Alu.cs"
)

Write-Host "Repositorio: $repo"
Write-Host "Pacote:      $packageRoot"
Write-Host ""

foreach ($relative in $relativeFiles) {
    $source = Join-Path $packageRoot $relative
    $destination = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Arquivo do pacote nao encontrado: $source"
    }

    if (-not (Test-Path -LiteralPath $destination)) {
        throw "Arquivo do repositorio nao encontrado: $destination"
    }

    $backup = Join-Path $backupRoot $relative
    New-Item -ItemType Directory -Force `
        -Path (Split-Path -Parent $backup) | Out-Null

    Copy-Item -LiteralPath $destination `
        -Destination $backup `
        -Force

    Copy-Item -LiteralPath $source `
        -Destination $destination `
        -Force

    Write-Host "Aplicado: $relative"
}

$vulkanSource = Join-Path $repo `
    "src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs"

$vsadLine = Select-String `
    -LiteralPath $vulkanSource `
    -SimpleMatch 'case "VSadU32":'

if (-not $vsadLine) {
    throw "VSadU32 nao foi encontrado no fonte aplicado."
}

Write-Host ""
Write-Host "VSadU32 confirmado na linha $($vsadLine.LineNumber)."
Write-Host "Backup: $backupRoot"
Write-Host ""

Get-Process -Name "SharpEmu" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$cliProject = Join-Path $repo `
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"

$runtimeOutput = Join-Path $repo `
    "artifacts\bin\Debug\net10.0\win-x64"

Write-Host "Limpando o CLI..."
dotnet clean $cliProject -c Debug -r win-x64
if ($LASTEXITCODE -ne 0) {
    throw "Falha no dotnet clean."
}

if (Test-Path -LiteralPath $runtimeOutput) {
    Remove-Item -LiteralPath $runtimeOutput `
        -Recurse `
        -Force
}

Write-Host ""
Write-Host "Reconstruindo o CLI e as dependencias..."
dotnet build $cliProject `
    -c Debug `
    -r win-x64 `
    --no-incremental

if ($LASTEXITCODE -ne 0) {
    throw "Falha no build do CLI."
}

$runtimeVulkan = Join-Path $runtimeOutput `
    "SharpEmu.ShaderCompiler.Vulkan.dll"
$runtimeMetal = Join-Path $runtimeOutput `
    "SharpEmu.ShaderCompiler.Metal.dll"
$runtimeExe = Join-Path $runtimeOutput "SharpEmu.exe"

foreach ($required in @(
    $runtimeVulkan,
    $runtimeMetal,
    $runtimeExe
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Arquivo runtime nao gerado: $required"
    }
}

Write-Host ""
Write-Host "Runtime atualizado:"
Get-Item $runtimeVulkan, $runtimeMetal, $runtimeExe |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize

$testProjects = @(
    "tests\SharpEmu.ShaderCompiler.Tests\SharpEmu.ShaderCompiler.Tests.csproj",
    "tests\SharpEmu.ShaderCompiler.Metal.Tests\SharpEmu.ShaderCompiler.Metal.Tests.csproj"
)

foreach ($relativeTest in $testProjects) {
    $testProject = Join-Path $repo $relativeTest

    if (Test-Path -LiteralPath $testProject) {
        Write-Host ""
        Write-Host "Executando: $relativeTest"
        dotnet test $testProject `
            -c Debug `
            --no-restore

        if ($LASTEXITCODE -ne 0) {
            throw "Falha em $relativeTest"
        }
    }
}

Write-Host ""
Write-Host "Correcao VSAD aplicada e runtime reconstruido."
Write-Host "Execute o jogo usando:"
Write-Host "& `"$runtimeExe`" `"F:\JOGOSPS5\PPSA25646-app\eboot.bin`" --log-level=debug --log-file=gpu_after_vsad_fix_v3.txt"
