$ErrorActionPreference = 'Stop'

$fixRoot = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$patchesRoot = [IO.Directory]::GetParent($fixRoot).FullName
$targetName = 'SharpEmu_V76_2_4_BinkGuestYuvIntegerSamplerFix_SAFE'
$targetRoot = [IO.Path]::Combine($patchesRoot, $targetName)
$validatePath = [IO.Path]::Combine($targetRoot, 'scripts', 'validate.ps1')
$manifestPath = [IO.Path]::Combine($targetRoot, 'manifest.sha256')
$run1Path = [IO.Path]::Combine($targetRoot, 'RUN_1_VALIDATE_PACKAGE.cmd')

foreach ($p in @($targetRoot, $validatePath, $manifestPath, $run1Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "alvo ausente: $p" }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = [IO.Path]::Combine($patchesRoot, "_V76_2_4_VALIDATOR_BACKUP_$stamp")
$backupZip = [IO.Path]::Combine($patchesRoot, "SharpEmu_V76_2_4_VALIDATOR_PREVIOUS_$stamp.zip")
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $validatePath -Destination ([IO.Path]::Combine($backupDir, 'validate.ps1')) -Force
Copy-Item -LiteralPath $manifestPath -Destination ([IO.Path]::Combine($backupDir, 'manifest.sha256')) -Force
Compress-Archive -LiteralPath ([IO.Path]::Combine($backupDir, '*')) -DestinationPath $backupZip -Force
Remove-Item -LiteralPath $backupDir -Recurse -Force
Write-Host "[V76.2.4.1] Backup=$backupZip"

$text = [IO.File]::ReadAllText($validatePath)
$original = $text

# 1) Replace the usual fragile root assignment when present.
$text = [regex]::Replace(
    $text,
    '(?mi)^\s*\$root\s*=\s*Get-PackageRoot\s*$[\r\n]*',
    "`$root = [IO.Path]::GetFullPath((Join-Path -Path `$PSScriptRoot -ChildPath '..')).Trim()`r`n"
)

# 2) Replace common manifest assignments when present.
$text = [regex]::Replace(
    $text,
    '(?mi)^\s*\$manifest\s*=\s*Join-Path\s+\$root\s+[''\"]manifest\.sha256[''\"]\s*$[\r\n]*',
    "`$manifest = [IO.Path]::Combine(`$root, 'manifest.sha256')`r`n"
)
$text = [regex]::Replace(
    $text,
    '(?mi)^\s*\$manifest\s*=\s*Join-Path\s+\$script:PackageRoot\s+[''\"]manifest\.sha256[''\"]\s*$[\r\n]*',
    "`$manifest = [IO.Path]::Combine([IO.Path]::GetFullPath((Join-Path -Path `$PSScriptRoot -ChildPath '..')).Trim(), 'manifest.sha256')`r`n"
)

# 3) Deterministic override immediately before first Test-Path($manifest).
# This is intentionally added even if the earlier replacements succeeded, so any noisy
# helper output can no longer pollute the path consumed by Test-Path.
$anchor = '(?mi)^\s*if\s*\(\s*-not\s*\(\s*Test-Path\s+-LiteralPath\s+\$manifest'
$m = [regex]::Match($text, $anchor)
if (-not $m.Success) {
    throw 'anchor Test-Path -LiteralPath $manifest nao encontrado; nenhuma alteracao gravada'
}
$bootstrap = @"
# V76.2.4.1 VALIDATOR PATH FIX: derive package root only from this script location.
`$root = [IO.Path]::GetFullPath((Join-Path -Path `$PSScriptRoot -ChildPath '..')).Trim()
`$manifest = [IO.Path]::Combine(`$root, 'manifest.sha256')
if ([string]::IsNullOrWhiteSpace(`$root) -or [string]::IsNullOrWhiteSpace(`$manifest)) {
    throw 'V76.2.4.1 package-root/manifest resolution failed'
}

"@
$text = $text.Insert($m.Index, $bootstrap)

if ($text -eq $original) { throw 'nenhuma alteracao produzida no validate.ps1' }

# Parse before writing.
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "validator corrigido nao parseia: $($parseErrors[0].Message)" }

[IO.File]::WriteAllText($validatePath, $text, [Text.UTF8Encoding]::new($false))
$newHash = (Get-FileHash -LiteralPath $validatePath -Algorithm SHA256).Hash.ToLowerInvariant()

# Update only the manifest entry for scripts/validate.ps1, preserving the path spelling.
$lines = [IO.File]::ReadAllLines($manifestPath)
$updated = 0
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^[0-9a-fA-F]{64}  (scripts[\\/]validate\.ps1)$') {
        $rel = $Matches[1]
        $lines[$i] = "$newHash  $rel"
        $updated++
    }
}
if ($updated -ne 1) {
    # rollback local two files before throwing
    # V76.2.4.2-BACKUP-MATERIALIZATION
    # A V76.2.4.1 calculava/logava $backupZip, mas podia chegar ao
    # Expand-Archive sem o arquivo ter sido materializado em Patches.
    if (-not (Test-Path -LiteralPath $backupZip -PathType Leaf)) {
        # V76.2.4.4 PATCHES_ROOT_INIT
        $v7624PatchesRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)        $v7624PreferredTarget = Join-Path $v7624PatchesRoot 'SharpEmu_V76_2_4_BinkGuestYuvIntegerSamplerFix_SAFE'
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
            throw "V76.2.4.2 nÃ£o conseguiu localizar de forma inequÃ­voca a pasta alvo V76.2.4 para criar o backup: $backupZip"
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
            throw "V76.2.4.2 backup nÃ£o foi materializado: $backupZip"
        }
        $v7624BackupInfo = Get-Item -LiteralPath $backupZip
        if ($v7624BackupInfo.Length -le 22) {
            throw "V76.2.4.2 backup invÃ¡lido/vazio: $backupZip bytes=$($v7624BackupInfo.Length)"
        }
        Write-Host "[V76.2.4.2] BackupMaterialized=$backupZip bytes=$($v7624BackupInfo.Length) source=$v7624BackupSource"
    }
    else {
        $v7624BackupInfo = Get-Item -LiteralPath $backupZip
        if ($v7624BackupInfo.Length -le 22) {
            throw "V76.2.4.2 backup existente Ã© invÃ¡lido/vazio: $backupZip bytes=$($v7624BackupInfo.Length)"
        }
        Write-Host "[V76.2.4.2] BackupReady=$backupZip bytes=$($v7624BackupInfo.Length)"
    }
    Expand-Archive -LiteralPath $backupZip -DestinationPath $env:TEMP\SharpEmuV7624ValidatorRollback -Force
    Copy-Item -LiteralPath ($env:TEMP + '\SharpEmuV7624ValidatorRollback\validate.ps1') -Destination $validatePath -Force
    Copy-Item -LiteralPath ($env:TEMP + '\SharpEmuV7624ValidatorRollback\manifest.sha256') -Destination $manifestPath -Force
    Remove-Item -LiteralPath ($env:TEMP + '\SharpEmuV7624ValidatorRollback') -Recurse -Force -ErrorAction SilentlyContinue
    throw "manifest entry scripts\\validate.ps1 count=$updated; rollback executado"
}
[IO.File]::WriteAllLines($manifestPath, $lines, [Text.UTF8Encoding]::new($false))

Write-Host "[V76.2.4.1] validate.ps1 patched sha256=$newHash" -ForegroundColor Green
Write-Host '[V76.2.4.1] Re-running original V76.2.4 RUN_1...' -ForegroundColor Cyan

& $run1Path
$exit = $LASTEXITCODE
if ($exit -ne 0) {
    Write-Host '[V76.2.4.1] Original RUN_1 still failed. Restoring validator+manifest backup...' -ForegroundColor Yellow
    $rb = [IO.Path]::Combine($env:TEMP, "SharpEmuV7624ValidatorRollback_$stamp")
    New-Item -ItemType Directory -Force -Path $rb | Out-Null
    Expand-Archive -LiteralPath $backupZip -DestinationPath $rb -Force
    Copy-Item -LiteralPath ([IO.Path]::Combine($rb, 'validate.ps1')) -Destination $validatePath -Force
    Copy-Item -LiteralPath ([IO.Path]::Combine($rb, 'manifest.sha256')) -Destination $manifestPath -Force
    Remove-Item -LiteralPath $rb -Recurse -Force
    throw "V76.2.4 original RUN_1 continuou falhando; validator/manifest restaurados. exit=$exit"
}

Write-Host '[V76.2.4.1] ORIGINAL V76.2.4 RUN_1 PASSED.' -ForegroundColor Green
Write-Host '[V76.2.4.1] Continue agora com RUN_2/RUN_3/RUN_4 do pacote V76.2.4 original.' -ForegroundColor Green
