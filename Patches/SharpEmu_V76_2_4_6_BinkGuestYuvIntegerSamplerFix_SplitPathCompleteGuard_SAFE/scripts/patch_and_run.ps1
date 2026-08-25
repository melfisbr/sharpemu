param([string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')
$patches = Get-PatchesRoot $PatchesRoot
$target = Get-TargetPackage $patches
$runner = Get-TargetRunner $target
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $patches "_SharpEmu_V76_2_4_6_TARGET_SCRIPTS_PREVIOUS_$stamp"
$backupZip = Join-Path $patches "SharpEmu_V76_2_4_6_TARGET_SCRIPTS_PREVIOUS_$stamp.zip"
$resultLog = Join-Path $patches "SharpEmu_V76_2_4_6_TARGET_RETRY_$stamp.log"
$resultSummary = Join-Path $patches "SharpEmu_V76_2_4_6_SUMMARY_$stamp.txt"
$stdoutLog = Join-Path $patches "_SharpEmu_V76_2_4_6_STDOUT_$stamp.tmp.log"
$stderrLog = Join-Path $patches "_SharpEmu_V76_2_4_6_STDERR_$stamp.tmp.log"
$scripts = @(Get-ScriptFiles $target)
$manifest = Join-Path $target 'manifest.sha256'
$backupItems = @($scripts.FullName)
if (Test-Path -LiteralPath $manifest -PathType Leaf) { $backupItems += $manifest }
$mutated = $false

function Restore-TargetScriptsV76246 {
    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) { return }
    foreach ($source in @(Get-ChildItem -LiteralPath $backupDir -File -Recurse)) {
        $relative = Get-RelativeTargetPath $backupDir $source.FullName
        $destination = Join-Path $target $relative
        $parent = Split-Path -Parent $destination
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
    }
}

try {
    foreach ($item in $backupItems) {
        $relative = Get-RelativeTargetPath $target $item
        $destination = Join-Path $backupDir $relative
        $parent = Split-Path -Parent $destination
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $item -Destination $destination -Force
    }
    if (Test-Path -LiteralPath $backupZip) { Remove-Item -LiteralPath $backupZip -Force }
    Compress-Archive -Path (Join-Path $backupDir '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
    Write-Host "[$PackageTag] Backup=$backupZip"

    $modified = @()
    $replacementCount = 0
    foreach ($script in $scripts) {
        $repair = Repair-SplitPathCommands $script.FullName
        if ($repair.Changed) {
            $modified += $script.FullName
            $replacementCount += $repair.Replacements
        }
    }
    $mutated = $modified.Count -gt 0
    $manifestResult = Update-TargetManifest $target $modified
    [void](Test-TargetManifest $target)

    $remainingRaw = 0
    foreach ($script in @(Get-ScriptFiles $target)) {
        $remainingRaw += @(Get-SplitPathCommandSpans $script.FullName).Count
    }
    if ($remainingRaw -ne 0) { throw "Raw Split-Path ainda presente depois do repair: $remainingRaw" }

    Write-Host "[$PackageTag] scripts_patched=$($modified.Count) split_path_commands_rewritten=$replacementCount manifest_updated=$($manifestResult.Updated)"
    Write-Host "[$PackageTag] Reexecutando runner original via cmd.exe sem NativeCommandError pipeline: $runner"

    if (Test-Path -LiteralPath $stdoutLog) { Remove-Item -LiteralPath $stdoutLog -Force }
    if (Test-Path -LiteralPath $stderrLog) { Remove-Item -LiteralPath $stderrLog -Force }
    $commandLine = '"' + $runner + '"'
    $process = Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/d','/s','/c',$commandLine) `
        -WorkingDirectory $target `
        -Wait -PassThru `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog

    $combined = @()
    if (Test-Path -LiteralPath $stdoutLog) { $combined += @(Get-Content -LiteralPath $stdoutLog) }
    if (Test-Path -LiteralPath $stderrLog) { $combined += @(Get-Content -LiteralPath $stderrLog) }
    $combined | Set-Content -LiteralPath $resultLog -Encoding UTF8
    foreach ($line in $combined) { Write-Host $line }

    if ($process.ExitCode -ne 0) {
        throw "Target runner FAILED exit=$($process.ExitCode). Log=$resultLog"
    }

    @(
        "Tag=$PackageTag",
        'Status=TARGET_RUNNER_PASSED',
        "Target=$target",
        "Runner=$runner",
        "ScriptsPatched=$($modified.Count)",
        "SplitPathCommandsRewritten=$replacementCount",
        "TargetManifestEntriesUpdated=$($manifestResult.Updated)",
        "Backup=$backupZip",
        "ResultLog=$resultLog"
    ) | Set-Content -LiteralPath $resultSummary -Encoding UTF8
    Write-Host "[$PackageTag] TARGET RUNNER PASSED. Summary=$resultSummary"
}
catch {
    $message = $_.Exception.Message
    try {
        Restore-TargetScriptsV76246
        Write-Host "[$PackageTag] Emergency rollback of target package scripts COMPLETED." -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Rollback secundario falhou: $($_.Exception.Message)"
    }
    @(
        "Tag=$PackageTag",
        'Status=FAILED_ROLLBACK',
        "Error=$message",
        "Target=$target",
        "Backup=$backupZip",
        "ResultLog=$resultLog"
    ) | Set-Content -LiteralPath $resultSummary -Encoding UTF8
    throw "$message Summary=$resultSummary"
}
finally {
    foreach ($temporary in @($stdoutLog,$stderrLog)) {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $backupDir -PathType Container) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
