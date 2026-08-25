Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$guardScript = $null
$backupDir = Join-Path $script:PatchesRoot ("SharpEmu_V76_2_4_7_PREVIOUS_META_SCRIPTS_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$summary = Join-Path $script:PatchesRoot ("SharpEmu_V76_2_4_7_RUN_RESULT_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$backupZip = "$backupDir.zip"
$changed = $false

function Restore-MetaPackage {
    if (-not $guardScript) { return }
    $scriptBackup = Join-Path $backupDir 'guard_script.ps1'
    $manifestBackup = Join-Path $backupDir 'manifest.sha256'
    if (Test-Path -LiteralPath $scriptBackup) { Copy-Item -LiteralPath $scriptBackup -Destination $guardScript -Force }
    if (Test-Path -LiteralPath $manifestBackup) { Copy-Item -LiteralPath $manifestBackup -Destination $script:TargetV6Manifest -Force }
    Write-Tag "Emergency rollback of V76.2.4.6 meta-package COMPLETED."
}

try {
    & (Join-Path $PSScriptRoot 'validate.ps1')
    $guardScript = Get-TargetGuardScript
    $state = Get-ContainmentState $guardScript

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -LiteralPath $guardScript -Destination (Join-Path $backupDir 'guard_script.ps1') -Force
    Copy-Item -LiteralPath $script:TargetV6Manifest -Destination (Join-Path $backupDir 'manifest.sha256') -Force
    Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -Force
    Write-Tag "Backup=$backupZip"

    if ($state -eq 'Ready') {
        $text = [IO.File]::ReadAllText($guardScript)
        $lines = [regex]::Split($text, '\r?\n')
        $hit = -1
        $candidateVar = $null
        for($i=0; $i -lt $lines.Length; $i++) {
            if ($lines[$i].IndexOf('Path fora do pacote-alvo:', [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($lines[$i] -notmatch '^([ \t]*)throw\s+["''].*Path fora do pacote-alvo:\s*\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?.*["'']\s*$') { continue }
            if ($hit -ge 0) { throw "Mais de um throw de containment encontrado; recusa segura" }
            $hit = $i
            $indent = $Matches[1]
            $candidateVar = $Matches[2]
        }
        if ($hit -lt 0 -or [string]::IsNullOrWhiteSpace($candidateVar)) {
            throw "Não foi possível localizar de forma segura o throw/variável de 'Path fora do pacote-alvo'"
        }

        $originalThrow = $lines[$hit]
        $replacement = @(
            "$indent# [V76.2.4.7-CANONICAL-CONTAINMENT] The legacy outer guard may false-positive on already-canonical child paths.",
            "$indent`$__candidateV76247 = [IO.Path]::GetFullPath([string]`$$candidateVar)",
            "$indent`$__metaPackageRootV76247 = [IO.Directory]::GetParent(`$PSScriptRoot).FullName",
            "$indent`$__patchesRootV76247 = [IO.Directory]::GetParent(`$__metaPackageRootV76247).FullName",
            "$indent`$__targetRootV76247 = [IO.Path]::GetFullPath((Join-Path `$__patchesRootV76247 'SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)",
            "$indent`$__relativeV76247 = [IO.Path]::GetRelativePath(`$__targetRootV76247, `$__candidateV76247)",
            "$indent`$__outsideV76247 = [IO.Path]::IsPathRooted(`$__relativeV76247) -or `$__relativeV76247 -eq '..' -or `$__relativeV76247.StartsWith('..' + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal) -or `$__relativeV76247.StartsWith('..' + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::Ordinal)",
            "${indent}if (`$__outsideV76247) { $($originalThrow.TrimStart()) }",
            "$indent# Valid canonical descendant: continue patching the target package."
        )
        $newLines = [Collections.Generic.List[string]]::new()
        for($i=0; $i -lt $lines.Length; $i++) {
            if ($i -eq $hit) { foreach($r in $replacement) { $newLines.Add($r) }; continue }
            $newLines.Add($lines[$i])
        }
        [IO.File]::WriteAllLines($guardScript, $newLines, [Text.UTF8Encoding]::new($false))
        Assert-PowerShellParses $guardScript
        Update-TargetManifest $guardScript
        $changed = $true
        Write-Tag "Canonical containment guard installed in $guardScript candidate=$candidateVar"
    } elseif ($state -eq 'Applied') {
        Write-Tag "Canonical containment guard already installed; rerunning target workflow."
    } else {
        throw "Estado inesperado do guard: $state"
    }

    $run1 = Join-Path $script:TargetV6Root 'RUN_1_VALIDATE_PACKAGE.cmd'
    $run2 = Join-Path $script:TargetV6Root 'RUN_2_PRECHECK.cmd'
    $run3 = Join-Path $script:TargetV6Root 'RUN_3_PATCH_AND_RUN.cmd'
    if (-not (Test-Path -LiteralPath $run3)) {
        $cands = @(Get-ChildItem -LiteralPath $script:TargetV6Root -Filter 'RUN_3*.cmd' -File)
        if ($cands.Count -ne 1) { throw "RUN_3 da V76.2.4.6 não pôde ser resolvido de forma unívoca" }
        $run3 = $cands[0].FullName
    }
    foreach($p in @($run1,$run2,$run3)) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Runner ausente: $p" } }

    & $run1
    if ($LASTEXITCODE -ne 0) { throw "V76.2.4.6 RUN_1 falhou após CanonicalContainmentFix" }
    & $run2
    if ($LASTEXITCODE -ne 0) { throw "V76.2.4.6 RUN_2 falhou após CanonicalContainmentFix" }
    & $run3
    if ($LASTEXITCODE -ne 0) { throw "V76.2.4.6 RUN_3 falhou após CanonicalContainmentFix" }

    $finalState = Get-ContainmentState $guardScript
    if ($finalState -ne 'Applied') { throw "State verify falhou após execução: $finalState" }
    $out = @(
        "Tag=$script:Tag",
        "GuardScript=$guardScript",
        "GuardState=$finalState",
        "TargetV6=$script:TargetV6Root",
        "TargetV1=$script:TargetV1Root",
        "TargetWorkflow=PASSED",
        "Backup=$backupZip"
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($summary, $out + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Tag "TARGET WORKFLOW PASSED. Summary=$summary"
} catch {
    $message = $_.Exception.Message
    if ($changed) { Restore-MetaPackage }
    [IO.File]::WriteAllText($summary, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    throw "$message Summary=$summary"
}
