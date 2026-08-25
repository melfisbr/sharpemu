. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate.ps1"
$repo=Get-RepoRoot $env:SHARPEMU_REPO_ROOT
$patches=Get-PatchesRoot $env:SHARPEMU_PATCHES_ROOT
$state=Get-PackageState $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $patches "SharpEmu_V76_0_10_PREVIOUS_FILES_$stamp.zip"
$buildLog=Join-Path $patches "SharpEmu_V76_0_10_BUILD_$stamp.log"
$summary=Join-Path $patches "SharpEmu_V76_0_10_SUMMARY_$stamp.txt"
$result=Join-Path $patches "SharpEmu_V76_0_10_RESULT_$stamp.zip"
$changed=$false
$temp=Join-Path ([System.IO.Path]::GetTempPath()) ("SharpEmu_V76_0_10_"+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    if ($state -eq 'Ready') {
        $backupMain=Join-Path $temp $MainRel
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupMain) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $MainRel) -Destination $backupMain -Force
        Compress-Archive -Path (Join-Path $temp 'src') -DestinationPath $backup -CompressionLevel Fastest
        Copy-Item -LiteralPath (Join-Path $PackageRoot 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs') -Destination (Join-Path $repo $MainRel) -Force
        Copy-Item -LiteralPath (Join-Path $PackageRoot 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.DsSwizzleV7610.cs') -Destination (Join-Path $repo $HelperRel) -Force
        $changed=$true
    }
    Assert-Installed $repo
    Push-Location $repo
    try {
        $out=& dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug 2>&1
        $exit=$LASTEXITCODE
        $out | Tee-Object -FilePath $buildLog
    } finally { Pop-Location }
    if ($exit -ne 0) { throw "dotnet build falhou exit_code=$exit" }
    $lines=@(
        "Package=$PackageTag",
        "StateBefore=$state",
        "BuildExitCode=$exit",
        "MainSHA256=$(Get-Sha256 (Join-Path $repo $MainRel))",
        "HelperSHA256=$(Get-Sha256 (Join-Path $repo $HelperRel))",
        "Backup=$backup",
        "BuildLog=$buildLog"
    )
    $lines | Set-Content -LiteralPath $summary -Encoding UTF8
    Compress-Archive -Path $summary,$buildLog -DestinationPath $result -CompressionLevel Fastest
    Write-Host "[$PackageTag] BUILD PASSED" -ForegroundColor Green
    Write-Host "[$PackageTag] SUMMARY=$summary"
    Write-Host "[$PackageTag] RESULT=$result"
} catch {
    if ($changed) {
        Write-Warning "[$PackageTag] Falha; restaurando source anterior."
        if (Test-Path -LiteralPath $backup) {
            $restore=Join-Path ([System.IO.Path]::GetTempPath()) ("SharpEmu_V76_0_10_restore_"+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $restore -Force | Out-Null
            Expand-Archive -LiteralPath $backup -DestinationPath $restore -Force
            Copy-Item -LiteralPath (Join-Path $restore $MainRel) -Destination (Join-Path $repo $MainRel) -Force
            Remove-Item -LiteralPath $restore -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath (Join-Path $repo $HelperRel) -Force -ErrorAction SilentlyContinue
    }
    throw
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
