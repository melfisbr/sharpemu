$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Package
$state = Get-SourceState
if ($state -eq 'Missing') { throw "$Tag target ausente" }
if ($state -like 'Divergent:*') { throw "$Tag baseline divergente: $state" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$buildLog = Join-Path $Patches "SharpEmu_V76_0_4_1_BUILD_$stamp.log"
$summary = Join-Path $Patches "SharpEmu_V76_0_4_1_SUMMARY_$stamp.txt"
$result = Join-Path $Patches "SharpEmu_V76_0_4_1_RESULT_$stamp.zip"
$backupDir = Join-Path $Patches "_V76_0_4_1_BACKUP_$stamp"
$backupZip = Join-Path $Patches "SharpEmu_V76_0_4_1_PREVIOUS_FILES_$stamp.zip"

if ($state -eq 'V76.0.4-BrokenBuild') {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backupFile = Join-Path $backupDir "Gen5SpirvTranslator.Alu.cs"
    Copy-Item -LiteralPath $Target -Destination $backupFile -Force
    Compress-Archive -LiteralPath $backupFile -DestinationPath $backupZip -CompressionLevel Optimal -Force
    Copy-Item -LiteralPath $Payload -Destination $Target -Force
    if ((Get-FileSha $Target) -ne $ExpectedFixedSha) { throw "$Tag write verification failed" }
    Write-Host "$Tag applied minimal CS0136 rename fix. Backup=$backupZip"
} else {
    Write-Host "$Tag fix ja aplicado; build sera executado novamente."
}

Push-Location $Repo
try {
    $output = & dotnet build ".\src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug 2>&1
    $exitCode = $LASTEXITCODE
    $output | Tee-Object -FilePath $buildLog
} finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    if (Test-Path -LiteralPath $backupDir) {
        $backupFile = Join-Path $backupDir "Gen5SpirvTranslator.Alu.cs"
        if (Test-Path -LiteralPath $backupFile) { Copy-Item -LiteralPath $backupFile -Destination $Target -Force }
    }
    throw "$Tag BUILD FAILED exit_code=$exitCode. Source anterior restaurado. BuildLog=$buildLog"
}

$finalSha = Get-FileSha $Target
if ($finalSha -ne $ExpectedFixedSha) { throw "$Tag BUILD terminou mas source hash divergiu: $finalSha" }

@(
    "Tag=$Tag",
    "Timestamp=$stamp",
    "Build=PASSED",
    "Target=$TargetRel",
    "PreviousState=$state",
    "FixedSHA256=$ExpectedFixedSha",
    "BuildLog=$buildLog",
    "Backup=$backupZip"
) | Set-Content -LiteralPath $summary -Encoding UTF8

$tmpResult = Join-Path $Patches "_V76_0_4_1_RESULT_$stamp"
New-Item -ItemType Directory -Force -Path $tmpResult | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $tmpResult "Gen5SpirvTranslator.Alu.cs") -Force
Copy-Item -LiteralPath $buildLog -Destination $tmpResult -Force
Copy-Item -LiteralPath $summary -Destination $tmpResult -Force
Compress-Archive -Path (Join-Path $tmpResult '*') -DestinationPath $result -CompressionLevel Optimal -Force
Remove-Item -LiteralPath $tmpResult -Recurse -Force
if (Test-Path -LiteralPath $backupDir) { Remove-Item -LiteralPath $backupDir -Recurse -Force }

Write-Host "$Tag BUILD PASSED." -ForegroundColor Green
Write-Host "$Tag Summary=$summary"
Write-Host "$Tag Result=$result"
