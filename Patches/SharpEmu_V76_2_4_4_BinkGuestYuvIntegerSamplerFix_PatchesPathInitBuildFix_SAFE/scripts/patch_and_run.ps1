$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$state = Assert-TargetReadyOrApplied
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupZip = Join-Path $PatchesRoot "SharpEmu_V76_2_4_4_PREVIOUS_PATCH_TARGET_$stamp.zip"
$resultLog = Join-Path $PatchesRoot "SharpEmu_V76_2_4_4_RUNNER_$stamp.log"

if ($state -eq 'Ready') {
    $backupStage = Join-Path ([System.IO.Path]::GetTempPath()) ("sharpemu_v76244_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $backupStage | Out-Null
    try {
        $backupFile = Join-Path $backupStage 'patch_target.ps1'
        Copy-Item -LiteralPath $TargetScript -Destination $backupFile -Force
        Compress-Archive -LiteralPath $backupFile -DestinationPath $backupZip -Force
    }
    finally {
        Remove-Item -LiteralPath $backupStage -Recurse -Force -ErrorAction SilentlyContinue
    }

    $targetText = Get-Text $TargetScript
    $legacyMatches = [regex]::Matches($targetText, 'Join-Path\s+\$Patches\b')
    if ($legacyMatches.Count -lt 1) {
        throw "Nenhum Join-Path `$Patches encontrado no target."
    }

    # Derive the Patches root locally from this target script:
    # ...\Patches\<package>\scripts\patch_target.ps1
    # $PSScriptRoot = ...\<package>\scripts
    # parent(parent($PSScriptRoot)) = ...\Patches
    $firstLegacyIndex = $legacyMatches[0].Index
    $lineStart = $targetText.LastIndexOf("`n", $firstLegacyIndex)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }

    $indentMatch = [regex]::Match($targetText.Substring($lineStart, $firstLegacyIndex - $lineStart), '^\s*')
    $indent = $indentMatch.Value

    $initBlock = @"
$indent# V76.2.4.4 PATCHES_ROOT_INIT
$indent`$v7624PatchesRoot = Split-Path -Parent (Split-Path -Parent `$PSScriptRoot)
"@

    $targetText = $targetText.Insert($lineStart, $initBlock)
    $targetText = [regex]::Replace($targetText, 'Join-Path\s+\$Patches\b', 'Join-Path $v7624PatchesRoot')

    Set-TextUtf8NoBom $TargetScript $targetText

    $afterState = Get-TargetState
    if ($afterState -ne 'Applied') {
        $restoreStage = Join-Path ([System.IO.Path]::GetTempPath()) ("sharpemu_v76244_apply_restore_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $restoreStage | Out-Null
        try {
            Expand-Archive -LiteralPath $backupZip -DestinationPath $restoreStage -Force
            $restoreFile = Join-Path $restoreStage 'patch_target.ps1'
            if (Test-Path -LiteralPath $restoreFile) {
                Copy-Item -LiteralPath $restoreFile -Destination $TargetScript -Force
            }
        }
        finally {
            Remove-Item -LiteralPath $restoreStage -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw "Patch do target não ficou Applied: $afterState"
    }

    Write-Tag "Backup=$backupZip"
    Write-Tag "patch_target.ps1 corrigido: `$Patches removido do Join-Path e raiz local inicializada."
}
else {
    Write-Tag "patch_target.ps1 já está corrigido; reutilizando estado Applied."
}

Write-Tag "Reexecutando runner original: $TargetRunner"

& $TargetRunner 2>&1 | Tee-Object -FilePath $resultLog
$runnerExit = $LASTEXITCODE

if ($runnerExit -ne 0) {
    # Restore only our target-script edit. The original runner remains responsible
    # for its own source/package rollback semantics.
    if (Test-Path -LiteralPath $backupZip) {
        $restoreStage = Join-Path ([System.IO.Path]::GetTempPath()) ("sharpemu_v76244_restore_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $restoreStage | Out-Null
        try {
            Expand-Archive -LiteralPath $backupZip -DestinationPath $restoreStage -Force
            $restoreFile = Join-Path $restoreStage 'patch_target.ps1'
            if (Test-Path -LiteralPath $restoreFile) {
                Copy-Item -LiteralPath $restoreFile -Destination $TargetScript -Force
                Write-Tag "Target script rollback COMPLETED."
            }
        }
        finally {
            Remove-Item -LiteralPath $restoreStage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    throw "Runner V76.2.4.1 falhou após PatchesPathInitFix. exit=$runnerExit Log=$resultLog"
}

Write-Tag "RUNNER ORIGINAL PASSED. Log=$resultLog"
Write-Tag "V76.2.4.4 BUILD/FIX COMPLETED."
