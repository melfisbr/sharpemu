. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw
if(-not $mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17')){ throw "V1.8.17 source cache marker missing." }
$decl=Get-NativeWorkerMaxDeclaration -Text $wt
if($null -eq $decl){ throw "NativeWorkerMaxConcurrent declaration not found in applied source." }
$declText=($decl.Text -replace '\s+',' ').Trim()
if($declText -notmatch 'NativeWorkerMaxConcurrent\s*(?:=|=>)\s*16\b'){ throw "Expected applied worker cap 16, found: $declText" }
Write-Host "[DBFZ-BOOT-18175] Source already applied; rebuilding only."
Push-Location $repo
try {
    dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
    if($LASTEXITCODE -ne 0){ throw "dotnet build failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
Write-Host "[DBFZ-BOOT-18175] BUILD PASSED."
