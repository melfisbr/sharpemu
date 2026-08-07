param([string]$RepositoryRoot = (Get-Location).Path)
$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path $RepositoryRoot).Path
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backup = Join-Path $repo "artifacts\backup-controller-options-$stamp"
$files = @(
"src\SharpEmu.GUI\GuiSettings.cs",
"src\SharpEmu.GUI\PerGameSettings.cs",
"src\SharpEmu.GUI\MainWindow.axaml.cs",
"src\SharpEmu.GUI\MainWindow.GameOptions.cs",
"src\SharpEmu.GUI\MainWindow.axaml",
"src\SharpEmu.GUI\Languages\ar.json",
"src\SharpEmu.GUI\Languages\br.json",
"src\SharpEmu.GUI\Languages\de.json",
"src\SharpEmu.GUI\Languages\dk.json",
"src\SharpEmu.GUI\Languages\en.json",
"src\SharpEmu.GUI\Languages\es.json",
"src\SharpEmu.GUI\Languages\fr.json",
"src\SharpEmu.GUI\Languages\hu.json",
"src\SharpEmu.GUI\Languages\it.json",
"src\SharpEmu.GUI\Languages\ja.json",
"src\SharpEmu.GUI\Languages\ko.json",
"src\SharpEmu.GUI\Languages\nl.json",
"src\SharpEmu.GUI\Languages\pt.json",
"src\SharpEmu.GUI\Languages\ru.json",
"src\SharpEmu.GUI\Languages\tr.json"
"src\SharpEmu.Libs\Pad\PadExports.cs",
"src\SharpEmu.Libs\Audio\AudioOut2Exports.cs",
"src\SharpEmu.Libs\Voice\VoiceQoSExports.cs",
"src\SharpEmu.Core\Cpu\Emulation\BmiInstructionEmulator.cs"
)
foreach($relative in $files){
 $source=Join-Path $packageRoot $relative
 $dest=Join-Path $repo $relative
 if(!(Test-Path $source)){throw "Arquivo ausente no pacote: $source"}
 if(!(Test-Path $dest)){throw "Arquivo ausente no repositorio: $dest"}
 $bak=Join-Path $backup $relative
 New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak)|Out-Null
 Copy-Item $dest $bak -Force
 Copy-Item $source $dest -Force
 Write-Host "Aplicado: $relative"
}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "Backup: $backup"
Push-Location $repo
try {
 dotnet build --no-incremental
 if($LASTEXITCODE -ne 0){throw "Falha no build."}
} finally { Pop-Location }
dotnet test (Join-Path $repo "tests\SharpEmu.Libs.Tests\SharpEmu.Libs.Tests.csproj") --no-restore
if($LASTEXITCODE -ne 0){throw "Falha nos testes de Libs."}
Write-Host "Concluido. A opcao aparece em Opcoes > Renderizacao e nas configuracoes por jogo."
