. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo = Get-RepoRoot
$backup = Get-LatestRuntimeAuditBackup $repo
$currentFrontend = Find-PatchedFrontendSource $repo
$originalBackup = Find-OriginalFrontendBackup $backup
$guiProject = Get-GuiProject $repo

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$recoveryRoot = Join-Path $repo ('.sharpemu-hotfix-backup\RuntimeAudit_UI_V1_1_3_FrontendLocatorRollback_' + $stamp)
New-Item -ItemType Directory -Force -Path $recoveryRoot | Out-Null

Get-Process -Name 'SharpEmu','SharpEmu.GUI' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$currentHash = Get-HashSafe $currentFrontend
if ($currentHash -ne $script:OriginalFrontendHash) {
    $safeName = ([IO.Path]::GetFileName($currentFrontend) + '.patched')
    Copy-Item -LiteralPath $currentFrontend -Destination (Join-Path $recoveryRoot $safeName) -Force
    Copy-Item -LiteralPath $originalBackup -Destination $currentFrontend -Force
    $restoredHash = Get-HashSafe $currentFrontend
    if ($restoredHash -ne $script:OriginalFrontendHash) {
        throw "$script:Tag Frontend restore hash mismatch: $restoredHash"
    }
    Write-Step "Frontend restored: $currentFrontend"
    Write-Step "RestoredSHA256=$restoredHash"
}
else {
    Write-Step "Frontend already equals pre-RuntimeAudit baseline."
}

# Quarantine only separate RuntimeAudit partials; never move the restored frontend itself.
$partials = @(Find-FileByHash (Join-Path $repo 'src') $script:RuntimeAuditPartialHash '*.cs')
if ($partials.Count -eq 0) {
    $partials = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.FullName -eq $currentFrontend) { return $false }
            $t = Get-Content -LiteralPath $_.FullName -Raw
            $t -match 'InstallRuntimeAuditButton' -or $t -match 'Audit\s*&\s*Launch'
        })
}
foreach ($p in $partials) {
    $dest = Join-Path $recoveryRoot ([IO.Path]::GetFileName($p.FullName) + '.runtimeaudit_quarantined_' + [guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $p.FullName -Destination $dest -Force
    Write-Step "Quarantined RuntimeAudit partial=$($p.FullName)"
}

# Remove only ProjectReference(s) targeting SharpEmu.RuntimeAudit.
$projectText = Get-Content -LiteralPath $guiProject -Raw
if ($projectText -match 'SharpEmu\.RuntimeAudit') {
    Copy-Item -LiteralPath $guiProject -Destination (Join-Path $recoveryRoot ([IO.Path]::GetFileName($guiProject) + '.before')) -Force
    [xml]$xml = $projectText
    $nodes = @()
    foreach ($ig in @($xml.Project.ItemGroup)) {
        foreach ($pr in @($ig.ProjectReference)) {
            if ($null -ne $pr -and [string]$pr.Include -match 'SharpEmu\.RuntimeAudit') {
                $nodes += $pr
            }
        }
    }
    foreach ($node in $nodes) {
        [void]$node.ParentNode.RemoveChild($node)
    }
    $xml.Save($guiProject)
    Write-Step "Removed GUI ProjectReference(s) to SharpEmu.RuntimeAudit=$($nodes.Count)"
}

Push-Location $repo
try {
    Write-Step "Building SharpEmu.GUI Debug win-x64..."
    & dotnet build $guiProject -c Debug -r win-x64 --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "$script:Tag GUI build failed after rollback (exit $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

$guiOut = Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64'
$logDir = Join-Path $repo 'RuntimeAuditStartupRecovery'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir ('startup_' + $stamp + '_stdout.log')
$stderr = Join-Path $logDir ('startup_' + $stamp + '_stderr.log')

$exeCandidates = @(
    (Join-Path $guiOut 'SharpEmu.GUI.exe'),
    (Join-Path $guiOut 'SharpEmu.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

$dllCandidates = @(
    (Join-Path $guiOut 'SharpEmu.GUI.dll'),
    (Join-Path $guiOut 'SharpEmu.dll')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

if ($exeCandidates.Count -gt 0) {
    $launch = $exeCandidates[0]
    Write-Step "StartupProbeExecutable=$launch"
    $proc = Start-Process -FilePath $launch -WorkingDirectory $guiOut -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
}
elseif ($dllCandidates.Count -gt 0) {
    $launch = $dllCandidates[0]
    Write-Step "StartupProbe=dotnet $launch"
    $proc = Start-Process -FilePath 'dotnet' -ArgumentList @($launch) -WorkingDirectory $guiOut -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
}
else {
    throw "$script:Tag No SharpEmu GUI executable/DLL found under $guiOut"
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
    throw "$script:Tag FRONTEND STARTUP STILL FAILING. Run RUN_4_COLLECT_STARTUP_DIAGNOSTIC.cmd."
}

Write-Step "SharpEmu process survived startup probe. PID=$($proc.Id)"
Write-Step "STARTUP ROLLBACK TEST PASSED."
Write-Step "RuntimeAudit frontend integration is disabled; non-RuntimeAudit emulator changes remain intact."
Write-Step "RecoveryBackup=$recoveryRoot"
Write-Step "SharpEmu was left running for visual confirmation."
