param([string]$RepoRoot='')
$script:PackageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$repo = Resolve-SharpEmuRepo $RepoRoot
$state = Get-SourceState $repo
$patches = Join-Path $repo 'Patches'
if (-not (Test-Path -LiteralPath $patches)) { New-Item -ItemType Directory -Path $patches | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $patches ("SharpEmu_V74_0_75_PROCESSING_FLOW_BUILD_{0}.log" -f $stamp)
$backupRoot = Join-Path $patches (".V74_0_75_processing_flow_backup_{0}" -f $stamp)
$presenter = Join-Path $repo $script:PresenterRel
$agc = Join-Path $repo $script:AgcRel
$backedUp = $false
$changed = $false
$beforePresenter = Get-Sha256 $presenter
$beforeAgc = Get-Sha256 $agc
try {
    if ($state.PresenterState -ne 'v74075' -or $state.AgcState -ne 'v74075') {
        foreach ($rel in @($script:PresenterRel, $script:AgcRel)) {
            $src = Join-Path $repo $rel
            $dst = Join-Path $backupRoot $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        $backedUp = $true
    }

    if ($state.PresenterState -eq 'needs-patch') {
        if (Apply-PresenterAliasPatch $presenter) { $changed = $true; Write-Host "$script:Tag presenter alias patch applied." }
    } elseif ($state.PresenterState -eq 'v74056332-compatible') {
        Write-Host "$script:Tag Existing V74.0.56.33.2 sampler alias preserved; no presenter rewrite needed."
    }

    if ($state.AgcState -eq 'needs-patch') {
        if (Apply-AgcFlowPatch $agc) { $changed = $true; Write-Host "$script:Tag AGC processing-flow patch applied." }
    }

    Assert-PatchedStructure $repo
    $afterPresenter = Get-Sha256 $presenter
    $afterAgc = Get-Sha256 $agc
    Write-Host "$script:Tag PATCH STRUCTURE PASSED."
    Write-Host "$script:Tag presenter_before=$beforePresenter"
    Write-Host "$script:Tag presenter_after=$afterPresenter"
    Write-Host "$script:Tag agc_before=$beforeAgc"
    Write-Host "$script:Tag agc_after=$afterAgc"
    if ($backedUp) { Write-Host "$script:Tag Backup: $backupRoot" }

    $project = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    "[$(Get-Date -Format o)] V74.0.75 BUILD START repo=$repo" | Set-Content -LiteralPath $logPath -Encoding UTF8
    Push-Location $repo
    try {
        & dotnet build $project -c Debug 2>&1 | Tee-Object -FilePath $logPath -Append
        $buildExit = $LASTEXITCODE
    } finally { Pop-Location }
    if ($buildExit -ne 0) { throw "$script:Tag dotnet build falhou com exit code $buildExit" }

    Assert-PatchedStructure $repo
    if ($backedUp -and $changed) {
        Set-Content -LiteralPath (Join-Path $patches '.V74_0_75_processing_flow_last_backup.txt') -Value $backupRoot -Encoding ASCII
    }
    Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format o)] V74.0.75 BUILD PASSED presenter=$(Get-Sha256 $presenter) agc=$(Get-Sha256 $agc)"
    Write-Host "$script:Tag BUILD PASSED."
    Write-Host "$script:Tag log=$logPath"
} catch {
    if ($backedUp) {
        Write-Host "$script:Tag APPLY/BUILD FAILED; restoring accumulated source backup..."
        foreach ($rel in @($script:PresenterRel, $script:AgcRel)) {
            $src = Join-Path $backupRoot $rel
            $dst = Join-Path $repo $rel
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst -Force }
        }
        Write-Host "$script:Tag ROLLBACK COMPLETED."
    }
    throw
}
