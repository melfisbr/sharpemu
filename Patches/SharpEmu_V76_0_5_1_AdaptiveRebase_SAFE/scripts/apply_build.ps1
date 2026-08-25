param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
& (Join-Path $PSScriptRoot 'validate.ps1')

$stateInfo = Get-SourceState $repo
if ($stateInfo.State -eq 'Divergent') {
    foreach ($unknown in $stateInfo.Unknown) { Write-Host "  $unknown" -ForegroundColor Red }
    throw 'APPLY recusado: o source mudou novamente; nenhum arquivo foi alterado.'
}

Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupZip = Join-Path $patches "SharpEmu_V76_0_5_1_PREVIOUS_FILES_$stamp.zip"
$buildLog = Join-Path $patches "SharpEmu_V76_0_5_1_BUILD_$stamp.log"
$summaryPath = Join-Path $patches "SharpEmu_V76_0_5_1_SUMMARY_$stamp.txt"
$resultZip = Join-Path $patches "SharpEmu_V76_0_5_1_RESULT_$stamp.zip"
$tempRoot = Join-Path $env:TEMP "SharpEmu_V76_0_5_1_$stamp"
$backupRoot = Join-Path $tempRoot 'backup'
$resultRoot = Join-Path $tempRoot 'result'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null

$mayChange = @(
    $BackendRel,
    $PresenterRel,
    $AluRel,
    $TranslatorRel,
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.BarriersV7604.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftFailV7604.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.CacheV7603.cs'
)

$addedByThisRun = New-Object System.Collections.Generic.List[string]
$backedUp = New-Object System.Collections.Generic.List[string]
$sourceMutated = $false
$buildPassed = $false
$rollbackCompleted = $false

try {
    foreach ($rel in $mayChange) {
        $target = Join-Path $repo $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $backupFile = Join-Path $backupRoot $rel
            $backupDir = Split-Path -Parent $backupFile
            if (-not (Test-Path -LiteralPath $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $target -Destination $backupFile -Force
            $backedUp.Add($rel)
        }
        elseif ($NewPayloadHashes.ContainsKey($rel)) {
            $addedByThisRun.Add($rel)
        }
    }

    if ($backedUp.Count -gt 0) {
        Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
        Write-Host "[$PackageTag] Backup=$backupZip"
    }

    # Backend is safe to replace wholesale because RUN_2 accepted only the exact
    # baseline hash or the already-applied payload hash for this file.
    $backendPayload = Join-Path $PackageRoot ('payload\' + $BackendRel)
    Copy-Item -LiteralPath $backendPayload -Destination (Join-Path $repo $BackendRel) -Force
    $sourceMutated = $true

    foreach ($rel in $NewPayloadHashes.Keys) {
        $source = Join-Path $PackageRoot ('payload\' + $rel)
        $target = Join-Path $repo $rel
        $dir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
        $sourceMutated = $true
    }

    & (Join-Path $PSScriptRoot 'adaptive_patch.ps1') -RepoRoot $repo
    Assert-InstalledMarkers $repo
    Write-Host "[$PackageTag] ADAPTIVE APPLY VERIFY PASSED."

    $project = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Write-Host "[$PackageTag] Building $project (Release / win-x64)..."
    & dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit = $LASTEXITCODE

    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add("Tag=$PackageTag")
    $summary.Add("RepositoryRoot=$repo")
    $summary.Add("InitialState=$($stateInfo.State)")
    $summary.Add("BuildExitCode=$buildExit")
    $summary.Add("BuildLog=$buildLog")
    $summary.Add("Backup=$backupZip")
    $summary.Add('ApplyMode=adaptive-in-place; divergent files were not replaced wholesale')
    $summary.Add('Core=DS_SWIZZLE_B32; S_BITCMP0/1_B64; VCMPX const I32/U32; V_CVT_PK_U16_U32; V_DOT2C_F32_F16; S_BARRIER 0x948; binary SPIR-V cache')
    $summary.Add('Safety=V7604 soft-fail becomes opt-in when present; V7603 missing disk-cache reference neutralized only if its class is absent')

    if ($buildExit -ne 0) {
        $summary.Add('Build=FAILED')
        $summary.Add('Rollback=STARTED')
        foreach ($rel in $backedUp) {
            $backupFile = Join-Path $backupRoot $rel
            $target = Join-Path $repo $rel
            Copy-Item -LiteralPath $backupFile -Destination $target -Force
        }
        foreach ($rel in $addedByThisRun) {
            $target = Join-Path $repo $rel
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force
            }
        }
        $rollbackCompleted = $true
        $summary.Add('Rollback=COMPLETED')
        Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $resultRoot (Split-Path -Leaf $summaryPath))
        if (Test-Path -LiteralPath $buildLog) {
            Copy-Item -LiteralPath $buildLog -Destination (Join-Path $resultRoot (Split-Path -Leaf $buildLog))
        }
        Compress-Archive -Path (Join-Path $resultRoot '*') -DestinationPath $resultZip -CompressionLevel Optimal -Force
        throw "BUILD FAILED; rollback concluido. Resultado: $resultZip"
    }

    $buildPassed = $true
    $summary.Add('Build=PASSED')
    $summary.Add('Rollback=NOT_REQUIRED')
    $summary.Add('TraceHint=SHARPEMU_TRACE_SPIRV_CACHE=1; SHARPEMU_TRACE_COMPUTE_DISPATCH_TIMING=1; SHARPEMU_TRACE_PRESENT_CADENCE=1; SHARPEMU_TRACE_FRAME_STATS=1')
    Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8
    Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $resultRoot (Split-Path -Leaf $summaryPath))
    Copy-Item -LiteralPath $buildLog -Destination (Join-Path $resultRoot (Split-Path -Leaf $buildLog))
    Compress-Archive -Path (Join-Path $resultRoot '*') -DestinationPath $resultZip -CompressionLevel Optimal -Force

    Write-Host "[$PackageTag] BUILD PASSED."
    Write-Host "[$PackageTag] Summary=$summaryPath"
    Write-Host "[$PackageTag] Result=$resultZip"
}
catch {
    if ($sourceMutated -and -not $buildPassed -and -not $rollbackCompleted) {
        Write-Host "[$PackageTag] Exception depois do primeiro write; restaurando source..." -ForegroundColor Yellow
        foreach ($rel in $backedUp) {
            $backupFile = Join-Path $backupRoot $rel
            $target = Join-Path $repo $rel
            if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
                Copy-Item -LiteralPath $backupFile -Destination $target -Force
            }
        }
        foreach ($rel in $addedByThisRun) {
            $target = Join-Path $repo $rel
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force
            }
        }
        $rollbackCompleted = $true
        Write-Host "[$PackageTag] Emergency rollback COMPLETED." -ForegroundColor Yellow
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
