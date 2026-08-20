. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo = Get-RepoRoot
$frontend = Get-FrontendPath $repo
$guiProject = Get-GuiProject $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$recoveryRoot = Join-Path $repo ('.sharpemu-hotfix-backup\RuntimeAudit_UI_V1_1_4_StringPathResumeRollback_' + $stamp)
New-Item -ItemType Directory -Force -Path $recoveryRoot | Out-Null

Get-Process -Name 'SharpEmu','SharpEmu.GUI' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# MainWindow must remain exactly at the pre-RuntimeAudit SHA.
$frontendHash = Get-HashSafe $frontend
if ($frontendHash -ne $script:OriginalFrontendHash) {
    throw "$script:Tag Refusing to continue: frontend baseline changed since precheck."
}
Write-Step "Frontend baseline preserved: SHA256=$frontendHash"

# V1.1.3 bug fix: partial values are STRING PATHS, not FileInfo objects.
$partials = @(Find-RuntimeAuditPartialPaths $repo $frontend)
foreach ($partialPathValue in $partials) {
    $partialPath = [string]$partialPathValue
    if ([string]::IsNullOrWhiteSpace($partialPath)) { continue }
    if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf)) { continue }

    $name = [IO.Path]::GetFileName($partialPath)
    $dest = Join-Path $recoveryRoot ($name + '.runtimeaudit_quarantined')
    $i = 1
    while (Test-Path -LiteralPath $dest) {
        $dest = Join-Path $recoveryRoot ($name + ".runtimeaudit_quarantined_$i")
        $i++
    }

    Move-Item -LiteralPath $partialPath -Destination $dest -Force
    Write-Step "Quarantined RuntimeAudit partial=$partialPath"
    Write-Step "QuarantineDestination=$dest"
}

# Remove only a direct ProjectReference to SharpEmu.RuntimeAudit if one exists.
$projectText = Get-Content -LiteralPath $guiProject -Raw
if ($projectText -match 'SharpEmu\.RuntimeAudit') {
    Copy-Item -LiteralPath $guiProject -Destination (Join-Path $recoveryRoot 'SharpEmu.GUI.csproj.before') -Force
    [xml]$xml = $projectText
    $nodes = New-Object System.Collections.Generic.List[object]
    foreach ($ig in @($xml.Project.ItemGroup)) {
        if ($null -eq $ig) { continue }
        foreach ($pr in @($ig.ProjectReference)) {
            if ($null -ne $pr -and ([string]$pr.Include) -match 'SharpEmu\.RuntimeAudit') {
                $nodes.Add($pr)
            }
        }
    }
    foreach ($node in @($nodes)) {
        [void]$node.ParentNode.RemoveChild($node)
    }
    $xml.Save($guiProject)
    Write-Step "Removed GUI ProjectReference(s) to SharpEmu.RuntimeAudit=$($nodes.Count)"
}
else {
    Write-Step "GUI has no ProjectReference to SharpEmu.RuntimeAudit; no project edit required."
}

# Confirm no active RuntimeAudit UI marker remains in source.
$remaining = @(Find-RuntimeAuditPartialPaths $repo $frontend)
if ($remaining.Count -gt 0) {
    foreach ($r in $remaining) { Write-Step "RemainingRuntimeAuditMarker=$([string]$r)" }
    throw "$script:Tag RuntimeAudit frontend marker still remains after quarantine."
}

Push-Location $repo
try {
    Write-Step "Building SharpEmu.GUI Debug win-x64..."
    & dotnet build $guiProject -c Debug -r win-x64 --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "$script:Tag GUI build failed after rollback resume (exit $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

$guiOut = Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64'
$logDir = Join-Path $repo 'RuntimeAuditStartupRecovery'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir ('startup_v1_1_4_' + $stamp + '_stdout.log')
$stderr = Join-Path $logDir ('startup_v1_1_4_' + $stamp + '_stderr.log')

$exeCandidates = @(
    (Join-Path $guiOut 'SharpEmu.GUI.exe'),
    (Join-Path $guiOut 'SharpEmu.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

$dllCandidates = @(
    (Join-Path $guiOut 'SharpEmu.GUI.dll'),
    (Join-Path $guiOut 'SharpEmu.dll')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

if ($exeCandidates.Count -gt 0) {
    $launch = [string]$exeCandidates[0]
    Write-Step "StartupProbeExecutable=$launch"
    $proc = Start-Process -FilePath $launch -WorkingDirectory $guiOut -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
}
elseif ($dllCandidates.Count -gt 0) {
    $launch = [string]$dllCandidates[0]
    Write-Step "StartupProbe=dotnet $launch"
    $proc = Start-Process -FilePath 'dotnet' -ArgumentList @($launch) -WorkingDirectory $guiOut -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
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
    throw "$script:Tag FRONTEND STARTUP STILL FAILING. Run RUN_4_COLLECT_STARTUP_DIAGNOSTIC.cmd."
}

Write-Step "SharpEmu process survived startup probe. PID=$($proc.Id)"
Write-Step "STARTUP ROLLBACK TEST PASSED."
Write-Step "MainWindow remains at original SHA256=$($script:OriginalFrontendHash)"
Write-Step "RuntimeAudit frontend partial(s) have been quarantined."
Write-Step "RecoveryBackup=$recoveryRoot"
Write-Step "SharpEmu was left running for visual confirmation."
