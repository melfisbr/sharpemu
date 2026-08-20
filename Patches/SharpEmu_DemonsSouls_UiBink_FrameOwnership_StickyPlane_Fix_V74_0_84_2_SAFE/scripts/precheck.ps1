. "$PSScriptRoot\common.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1')
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$p=Presenter
$ps=[IO.File]::ReadAllText($p); $ps=NL $ps
if ($ps.Contains('SHARPEMU_V74_0_84_2_UI_BINK_FRAME_OWNERSHIP') -and
    $ps.Contains('SHARPEMU_V74_0_84_2_UI_BINK_STICKY_PLANE_INTEGRITY')) {
    Write-Host '[V74.0.84.2] State=AlreadyApplied' -ForegroundColor Yellow
    exit 10
}
foreach ($m in @(
    'SHARPEMU_V74_0_84_1_UI_BINK_COLOR_CONTRACT',
    'SHARPEMU_V74_0_84_1_UI_BINK_GUEST_CHROMA_ORDER',
    'NormalizeDemonSoulsUiBinkChromaV740841')) {
    if (-not $ps.Contains($m)) {
        Write-Host "[V74.0.84.2][ERROR] V84.1 prerequisite missing: $m" -ForegroundColor Red
        exit 1
    }
}
try {
    [void](FindMethodSpan $ps '(?m)^[ \t]*private void PumpHostMovieFrame\(\)\s*$' 'PumpHostMovieFrame')
    [void](FindMethodSpan $ps '(?m)^[ \t]*private HostMovieTextureBindings FindHostMovieTextureBindings\(' 'FindHostMovieTextureBindings')
    [void](FindMethodSpan $ps '(?m)^[ \t]*private HostMovieTextureBindings RememberHostMovieTextureMappings\(' 'RememberHostMovieTextureMappings')
} catch {
    Write-Host "[V74.0.84.2][ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
if ((CountExact $ps '        private long _v740841UiBinkChromaTraceCount;') -ne 1) {
    Write-Host '[V74.0.84.2][ERROR] V84.1 Presenter field anchor changed.' -ForegroundColor Red
    exit 1
}
Write-Host '[V74.0.84.2] Runtime evidence: main_menu is internal NIHAV and guest remains live, but the Bink background later corrupts while menu text remains readable.'
Write-Host '[V74.0.84.2] Fix A: presenter-owned immutable BGRA snapshot for each advanced UI-Bink frame.'
Write-Host '[V74.0.84.2] Fix B: learned Bluepoint Y/UV sampled planes remain host-substituted if a later draw exposes only one learned plane.'
Write-Host '[V74.0.84.2] Storage descriptors are never substituted; guest decoder compute writes remain untouched.'
Write-Host "[V74.0.84.2] PresenterSHA256=$(Sha $p)"
Write-Host '[V74.0.84.2] PRECHECK PASSED.' -ForegroundColor Green
