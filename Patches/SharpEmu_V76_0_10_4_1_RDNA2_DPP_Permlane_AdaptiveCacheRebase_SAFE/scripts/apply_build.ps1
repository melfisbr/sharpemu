. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate.ps1"

$repo = Get-RepoRoot $env:SHARPEMU_REPO_ROOT
$patches = Get-PatchesRoot $env:SHARPEMU_PATCHES_ROOT
$state = Get-PackageState $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $patches "SharpEmu_V76_0_10_4_1_PREVIOUS_FILES_$stamp.zip"
$buildLog = Join-Path $patches "SharpEmu_V76_0_10_4_1_BUILD_$stamp.log"
$summary = Join-Path $patches "SharpEmu_V76_0_10_4_1_SUMMARY_$stamp.txt"
$result = Join-Path $patches "SharpEmu_V76_0_10_4_1_RESULT_$stamp.zip"
$changed = $false
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("SharpEmu_V76_0_10_4_1_" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    if ($state -eq 'Ready') {
        foreach ($rel in @($AluRel, $CacheRel)) {
            $dst = Join-Path $temp $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $repo $rel) -Destination $dst -Force
        }
        Compress-Archive -Path (Join-Path $temp 'src') -DestinationPath $backup -CompressionLevel Fastest

        Copy-Item -LiteralPath (
            Join-Path $PackageRoot 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs') `
            -Destination (Join-Path $repo $AluRel) -Force

        Set-CacheVersionAdaptive (Join-Path $repo $CacheRel)
        $changed = $true
    }

    Assert-Installed $repo

    Push-Location $repo
    try {
        $out = & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug 2>&1
        $exit = $LASTEXITCODE
        $out | Tee-Object -FilePath $buildLog
    }
    finally {
        Pop-Location
    }

    if ($exit -ne 0) { throw "dotnet build falhou exit_code=$exit" }

    $cacheFinalHash = Get-Sha256 (Join-Path $repo $CacheRel)
    @(
        "Package=$PackageTag",
        "StateBefore=$state",
        "BuildExitCode=$exit",
        "AluSHA256=$(Get-Sha256 (Join-Path $repo $AluRel))",
        "CacheSHA256=$cacheFinalHash",
        "CacheVersion=$CacheVersionAfter",
        "AdaptiveCacheRebase=True",
        "V76103DsSwizzlePreserved=True",
        "Backup=$backup",
        "BuildLog=$buildLog"
    ) | Set-Content -LiteralPath $summary -Encoding UTF8

    Compress-Archive -Path $summary,$buildLog -DestinationPath $result -CompressionLevel Fastest
    Write-Host "[$PackageTag] BUILD PASSED" -ForegroundColor Green
    Write-Host "[$PackageTag] SUMMARY=$summary"
    Write-Host "[$PackageTag] RESULT=$result"
}
catch {
    if ($changed -and (Test-Path -LiteralPath $backup)) {
        Write-Warning "[$PackageTag] Falha; restaurando source anterior."
        $restore = Join-Path ([System.IO.Path]::GetTempPath()) ("SharpEmu_V76_0_10_4_1_restore_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $restore -Force | Out-Null
        try {
            Expand-Archive -LiteralPath $backup -DestinationPath $restore -Force
            foreach ($rel in @($AluRel, $CacheRel)) {
                Copy-Item -LiteralPath (Join-Path $restore $rel) -Destination (Join-Path $repo $rel) -Force
            }
        }
        finally {
            Remove-Item -LiteralPath $restore -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    throw
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
