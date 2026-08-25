. (Join-Path $PSScriptRoot 'common.ps1')
Assert-TargetPackage
Assert-PowerShellParses $TargetScript
$text = Get-Text $TargetScript

if (-not $text.Contains($Marker)) {
    $anchorMatches = [regex]::Matches($text,'(?im)^\s*Expand-Archive\s+-LiteralPath\s+\$backupZip\b.*$')
    if ($anchorMatches.Count -lt 1) { throw 'Anchor do Expand-Archive de $backupZip não encontrado.' }
    # V76.2.4.3: V76.2.4.1 possui dois restore sites legítimos. Injeta antes do primeiro;
    # o ZIP materializado serve também ao segundo rollback.
    $anchor = $anchorMatches[0]
    Write-Host "$Tag BackupRestoreAnchors=$($anchorMatches.Count) Selected=first"

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $scriptBackupZip = Join-Path $Patches "SharpEmu_V76_2_4_3_PREVIOUS_PATCH_TARGET_$stamp.zip"
    $tempBackupDir = Join-Path $env:TEMP "SharpEmu_V76_2_4_3_patch_target_$stamp"
    New-Item -ItemType Directory -Path $tempBackupDir -Force | Out-Null
    Copy-Item -LiteralPath $TargetScript -Destination (Join-Path $tempBackupDir 'patch_target.ps1') -Force
    Compress-Archive -LiteralPath (Join-Path $tempBackupDir 'patch_target.ps1') -DestinationPath $scriptBackupZip -CompressionLevel Optimal -Force
    Remove-Item -LiteralPath $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $scriptBackupZip -PathType Leaf)) { throw "Falha ao criar backup do patch_target: $scriptBackupZip" }
    Write-Host "$Tag ValidatorScriptBackup=$scriptBackupZip"

    $snippet = @'
    # V76.2.4.2-BACKUP-MATERIALIZATION
    # A V76.2.4.1 calculava/logava $backupZip, mas podia chegar ao
    # Expand-Archive sem o arquivo ter sido materializado em Patches.
    if (-not (Test-Path -LiteralPath $backupZip -PathType Leaf)) {
        $v7624PreferredTarget = Join-Path $Patches 'SharpEmu_V76_2_4_BinkGuestYuvIntegerSamplerFix_SAFE'
        $v7624BackupSource = $null

        if (Test-Path -LiteralPath $v7624PreferredTarget -PathType Container) {
            $v7624BackupSource = $v7624PreferredTarget
        }
        else {
            $v7624Candidates = @(Get-ChildItem -LiteralPath $Patches -Directory -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -like 'SharpEmu_V76_2_4_*' -and
                $_.Name -notlike 'SharpEmu_V76_2_4_1_*' -and
                $_.Name -notlike 'SharpEmu_V76_2_4_2_*' -and
                $_.Name -notlike '*VALIDATOR_PREVIOUS*'
            } | Sort-Object Name)
            if ($v7624Candidates.Count -eq 1) {
                $v7624BackupSource = $v7624Candidates[0].FullName
            }
            elseif ($v7624Candidates.Count -gt 1) {
                $v7624Strong = @($v7624Candidates | Where-Object {
                    Test-Path -LiteralPath (Join-Path $_.FullName 'scripts') -PathType Container
                })
                if ($v7624Strong.Count -eq 1) { $v7624BackupSource = $v7624Strong[0].FullName }
            }
        }

        if ([string]::IsNullOrWhiteSpace($v7624BackupSource)) {
            throw "V76.2.4.2 não conseguiu localizar de forma inequívoca a pasta alvo V76.2.4 para criar o backup: $backupZip"
        }

        $v7624BackupParent = Split-Path -Parent $backupZip
        if (-not (Test-Path -LiteralPath $v7624BackupParent -PathType Container)) {
            New-Item -ItemType Directory -Path $v7624BackupParent -Force | Out-Null
        }
        if (Test-Path -LiteralPath $backupZip) {
            Remove-Item -LiteralPath $backupZip -Force
        }

        Compress-Archive -Path (Join-Path $v7624BackupSource '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
        if (-not (Test-Path -LiteralPath $backupZip -PathType Leaf)) {
            throw "V76.2.4.2 backup não foi materializado: $backupZip"
        }
        $v7624BackupInfo = Get-Item -LiteralPath $backupZip
        if ($v7624BackupInfo.Length -le 22) {
            throw "V76.2.4.2 backup inválido/vazio: $backupZip bytes=$($v7624BackupInfo.Length)"
        }
        Write-Host "[V76.2.4.2] BackupMaterialized=$backupZip bytes=$($v7624BackupInfo.Length) source=$v7624BackupSource"
    }
    else {
        $v7624BackupInfo = Get-Item -LiteralPath $backupZip
        if ($v7624BackupInfo.Length -le 22) {
            throw "V76.2.4.2 backup existente é inválido/vazio: $backupZip bytes=$($v7624BackupInfo.Length)"
        }
        Write-Host "[V76.2.4.2] BackupReady=$backupZip bytes=$($v7624BackupInfo.Length)"
    }
'@

    $newText = $text.Insert($anchor.Index, $snippet + [Environment]::NewLine)
    Write-Utf8NoBom $TargetScript $newText
    Assert-PowerShellParses $TargetScript
    $check = Get-Text $TargetScript
    if (-not $check.Contains($Marker)) { throw 'Marker V76.2.4.2 não persistiu no patch_target.ps1' }
    Write-Host "$Tag patch_target.ps1 corrigido."
}
else {
    Write-Host "$Tag patch_target.ps1 já contém o fix; reaplicação não necessária."
}

# Reexecuta o caminho original que chama patch_target.ps1 quando detectável.
$runnerPath = Get-RepairRunner
if ($null -ne $runnerPath) {
    Write-Host "$Tag Reexecutando runner original: $runnerPath"
    & $runnerPath
    if ($LASTEXITCODE -ne 0) { throw "Runner V76.2.4.1 falhou após BackupMaterializationFix. exit=$LASTEXITCODE" }
}
else {
    Write-Host "$Tag Runner CMD não localizado; executando patch_target.ps1 diretamente."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TargetScript
    if ($LASTEXITCODE -ne 0) { throw "patch_target.ps1 V76.2.4.1 falhou após fix. exit=$LASTEXITCODE" }
}

Write-Host "$Tag REPAIR + REVALIDATE PASSED."
