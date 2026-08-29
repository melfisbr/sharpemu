$ErrorActionPreference = "Stop"

$Patches = "C:\Users\Edpo\Documents\GitHub\sharpemu\Patches"
$PackageSource = Join-Path $PSScriptRoot "packages"

Set-Location $Patches

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$Sequence = @(
    @{
        Zip = "SharpEmu_V76_3_18_0_RPCS3Inspired_QueueArchitectureMerge_DEV_SAFE.zip"
        Dir = "SharpEmu_V76_3_18_0_RPCS3Inspired_QueueArchitectureMerge_DEV_SAFE"
    },
    @{
        Zip = "SharpEmu_V76_3_18_1_ResidentWorkingSet_CacheMerge_DEV_SAFE.zip"
        Dir = "SharpEmu_V76_3_18_1_ResidentWorkingSet_CacheMerge_DEV_SAFE"
    },
    @{
        Zip = "SharpEmu_V76_3_18_2_EventDrivenWaitGraph_Watchdog_DEV_SAFE.zip"
        Dir = "SharpEmu_V76_3_18_2_EventDrivenWaitGraph_Watchdog_DEV_SAFE"
    },
    @{
        Zip = "SharpEmu_V76_3_18_3_ShaderFrontendScratchPool_DEV_SAFE.zip"
        Dir = "SharpEmu_V76_3_18_3_ShaderFrontendScratchPool_DEV_SAFE"
    },
    @{
        Zip = "SharpEmu_V76_3_18_4_GuestFPS_BinkExcluded_FinalDiagnostic_DEV_SAFE.zip"
        Dir = "SharpEmu_V76_3_18_4_GuestFPS_BinkExcluded_FinalDiagnostic_DEV_SAFE"
    }
)

for ($i = 0; $i -lt $Sequence.Count; $i++) {
    $item = $Sequence[$i]
    $zip = Join-Path $PackageSource $item.Zip
    $dir = Join-Path $Patches $item.Dir

    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host (" ETAPA {0}/{1}: {2}" -f ($i + 1), $Sequence.Count, $item.Dir) -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $zip)) {
        throw "ZIP da etapa nao encontrado: $zip"
    }

    # O pacote e SEMPRE descompactado imediatamente antes de validate/precheck/apply.
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }

    Expand-Archive `
        -LiteralPath $zip `
        -DestinationPath $Patches `
        -Force

    Push-Location $dir
    try {
        .\RUN_1_VALIDATE_PACKAGE.cmd
        if ($LASTEXITCODE -ne 0) {
            throw "ETAPA $($i+1) RUN_1 falhou"
        }

        .\RUN_2_PRECHECK.cmd
        if ($LASTEXITCODE -ne 0) {
            throw "ETAPA $($i+1) RUN_2 falhou"
        }

        .\RUN_3_APPLY_BUILD.cmd
        if ($LASTEXITCODE -ne 0) {
            throw "ETAPA $($i+1) RUN_3 falhou"
        }

        # Nao executar jogos/testes intermediarios.
        if ($i -eq $Sequence.Count - 1) {
            Write-Host ""
            Write-Host "TODAS AS CORRECOES FORAM APLICADAS. INICIANDO O UNICO TESTE RUNTIME..." -ForegroundColor Green
            .\RUN_4_DIAGNOSTIC.cmd
            if ($LASTEXITCODE -ne 0) {
                throw "ETAPA FINAL RUN_4 falhou"
            }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " V76.3.18.0 -> V76.3.18.4 CONCLUIDO" -ForegroundColor Green
Write-Host " FPS BINK/FFMPEG HOST FOI EXCLUIDO DA METRICA guest_fps" -ForegroundColor Green
Write-Host " Verifique V76.3.18.4_SUMMARY_*.txt e RESULT_*.zip em Patches" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
