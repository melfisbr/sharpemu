. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo = Get-RepoRoot
$backup = Get-LatestRuntimeAuditBackup $repo
$main = Find-CurrentMainWindow $repo
$backupMain = @(Find-FileByHash $backup $script:OriginalMainWindowHash 'MainWindow.cs')[0]
$guiProject = Get-GuiProject $repo

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$recoveryRoot = Join-Path $repo ('.sharpemu-hotfix-backup\RuntimeAudit_UI_V1_1_2_StartupRollback_' + $stamp)
New-Item -ItemType Directory -Force -Path $recoveryRoot | Out-Null

Get-Process -Name 'SharpEmu','SharpEmu.GUI' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 1) Restore the exact MainWindow baseline recorded by the V1.1 log.
$currentHash = Get-HashSafe $main
if ($currentHash -eq $script:PatchedMainWindowHash) {
    Copy-Item -LiteralPath $main -Destination (Join-Path $recoveryRoot 'MainWindow.patched.cs') -Force
    Copy-Item -LiteralPath $backupMain -Destination $main -Force
    $restoredHash = Get-HashSafe $main
    if ($restoredHash -ne $script:OriginalMainWindowHash) {
        throw "$script:Tag MainWindow restore hash mismatch: $restoredHash"
    }
    Write-Step "MainWindow restored to pre-RuntimeAudit SHA256=$restoredHash"
}
elseif ($currentHash -eq $script:OriginalMainWindowHash) {
    Write-Step "MainWindow already equals pre-RuntimeAudit baseline."
}

# 2) Quarantine only RuntimeAudit partial(s) identified by exact hash or hook markers.
$partials = @(Find-FileByHash (Join-Path $repo 'src') $script:RuntimeAuditPartialHash '*.cs')
if ($partials.Count -eq 0) {
    $partials = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.FullName -eq $main) { return $false }
            $t = Get-Content -LiteralPath $_.FullName -Raw
            $t -match 'InstallRuntimeAuditButton' -or $t -match 'Audit\s*&\s*Launch'
        })
}
foreach ($p in $partials) {
    $dest = Join-Path $recoveryRoot ($p.BaseName + '.' + [guid]::NewGuid().ToString('N') + $p.Extension)
    Move-Item -LiteralPath $p.FullName -Destination $dest -Force
    Write-Step "Quarantined RuntimeAudit frontend partial: $($p.FullName)"
}

# 3) Remove only a GUI ProjectReference that points to SharpEmu.RuntimeAudit, if V1.1 added one.
$projectText = Get-Content -LiteralPath $guiProject -Raw
if ($projectText -match 'SharpEmu\.RuntimeAudit') {
    Copy-Item -LiteralPath $guiProject -Destination (Join-Path $recoveryRoot ([IO.Path]::GetFileName($guiProject) + '.with-runtimeaudit')) -Force
    [xml]$xml = $projectText
    $nodes = @($xml.Project.ItemGroup.ProjectReference | Where-Object { $_.Include -match 'SharpEmu\.RuntimeAudit' })
    foreach ($node in $nodes) {
        [void]$node.ParentNode.RemoveChild($node)
    }
    $xml.Save($guiProject)
    Write-Step "Removed GUI ProjectReference(s) to SharpEmu.RuntimeAudit: $($nodes.Count)"
}

# 4) Build the GUI cleanly.
$guiOut = Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64'
Push-Location $repo
try {
    Write-Step "Building SharpEmu.GUI Debug win-x64 after rollback..."
    & dotnet build $guiProject -c Debug -r win-x64 --nologo
    if ($LASTEXITCODE -ne 0) { throw "$script:Tag GUI build failed after rollback (exit $LASTEXITCODE)." }
}
finally {
    Pop-Location
}

# 5) Runtime startup probe. Prefer apphost executables, then dotnet DLL.
$exeCandidates = @(
    (Join-Path $guiOut 'SharpEmu.GUI.exe'),
    (Join-Path $guiOut 'SharpEmu.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

$dll = Join-Path $guiOut 'SharpEmu.GUI.dll'
$logDir = Join-Path $repo 'RuntimeAuditStartupRecovery'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir ('startup_' + $stamp + '_stdout.log')
$stderr = Join-Path $logDir ('startup_' + $stamp + '_stderr.log')

if ($exeCandidates.Count -gt 0) {
    $launch = $exeCandidates[0]
    Write-Step "Startup probe executable=$launch"
    $proc = Start-Process -FilePath $launch -WorkingDirectory $guiOut -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
}
elseif (Test-Path -LiteralPath $dll) {
    Write-Step "Startup probe=dotnet $dll"
    $proc = Start-Process -FilePath 'dotnet' -ArgumentList @($dll) -WorkingDirectory $guiOut -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
}
else {
    throw "$script:Tag No GUI executable/DLL found under $guiOut"
}

Start-Sleep -Seconds 6
$proc.Refresh()
if ($proc.HasExited) {
    Write-Warning "$script:Tag SharpEmu exited during startup probe. ExitCode=$($proc.ExitCode)"
    Write-Step "stdout=$stdout"
    Write-Step "stderr=$stderr"
    if (Test-Path -LiteralPath $stderr) {
        $err = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        if ($err) { Write-Host $err }
    }
    throw "$script:Tag FRONTEND STARTUP STILL FAILING. Run RUN_4_COLLECT_STARTUP_DIAGNOSTIC.cmd and send the generated ZIP."
}

Write-Step "SharpEmu process is still alive after startup probe (PID=$($proc.Id))."
Write-Step "STARTUP ROLLBACK TEST PASSED. The RuntimeAudit frontend hook is disabled; core emulator changes were preserved."
Write-Step "Recovery backup=$recoveryRoot"
Write-Step "The opened SharpEmu process was intentionally left running for visual confirmation."
