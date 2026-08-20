. "$PSScriptRoot\common.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1')
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$h=Host; $a=Assist; $p=Presenter
$hs=[IO.File]::ReadAllText($h); $hs=NL $hs
$as=[IO.File]::ReadAllText($a); $as=NL $as
$ps=[IO.File]::ReadAllText($p); $ps=NL $ps
if ($hs.Contains('SHARPEMU_V74_0_84_1_DEMONS_UI_BINK_INTERNAL_COMPOSITOR') -and
    $as.Contains('SHARPEMU_V74_0_84_1_UI_BINK_GUEST_LIVE_PASSTHROUGH') -and
    $ps.Contains('SHARPEMU_V74_0_84_1_UI_BINK_GUEST_CHROMA_ORDER')) {
    Write-Host '[V74.0.84.1] State=AlreadyApplied' -ForegroundColor Yellow
    exit 10
}
foreach ($m in @(
    'SHARPEMU_V74_0_77_2_DEMONS_ATTRACT_GUEST_COMPLETION',
    'SHARPEMU_V74_0_81_TITLE_LOOP_COMPOSITE_STATE',
    'SHARPEMU_V74_0_83_ACTIVE_MOVIE_PATH',
    'SHARPEMU_V74_0_83_NATURAL_INTRO_TITLE_CHAIN')) {
    if (-not $hs.Contains($m)) { Write-Host "[V74.0.84.1][ERROR] Host prerequisite missing: $m" -ForegroundColor Red; exit 1 }
}
foreach ($m in @('SHARPEMU_V74_0_77_DEMONS_TITLE_TIMELINE','SHARPEMU_V74_0_83_LOGO_INTRO_TITLE_PASSTHROUGH')) {
    if (-not $as.Contains($m)) { Write-Host "[V74.0.84.1][ERROR] Assist prerequisite missing: $m" -ForegroundColor Red; exit 1 }
}
foreach ($m in @('SHARPEMU_V74_0_81_TITLE_LOOP_UI_COMPOSITOR','SHARPEMU_V74_0_82_TITLE_LOOP_NONEXCLUSIVE','SHARPEMU_V74_0_83_ACTIVE_MOVIE_RECONCILE','SHARPEMU_V74_0_83_TITLE_UI_DRAW_DISCOVERY')) {
    if (-not $ps.Contains($m)) { Write-Host "[V74.0.84.1][ERROR] Presenter prerequisite missing: $m" -ForegroundColor Red; exit 1 }
}
try {
    [void](FindMethodSpan $hs '(?m)^[ \t]*private static void AttachMovieLocked\(string hostPath, MovieMode mode\)\s*$' 'AttachMovieLocked')
    [void](FindMethodSpan $ps '(?m)^[ \t]*private void EnsureHostMovieYuvFrame\(\)\s*$' 'EnsureHostMovieYuvFrame')
    $order=GetBaseChromaOrder $ps
} catch {
    Write-Host "[V74.0.84.1][ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
if ((CountExact $hs 'return IsTitleLoopPathV74081(_activePath) &&') -ne 1) { Write-Host '[V74.0.84.1][ERROR] V81 composite-state expression changed.' -ForegroundColor Red; exit 1 }
$assistAnchor=Patch 'Assist.ui_passthrough.anchor.txt'
if ((CountExact $as $assistAnchor) -ne 1) { Write-Host '[V74.0.84.1][ERROR] V83 passthrough block changed.' -ForegroundColor Red; exit 1 }
if ((CountExact $ps '        private long _v74083TitleUiCandidateCount;') -ne 1) { Write-Host '[V74.0.84.1][ERROR] V83 Presenter field anchor changed.' -ForegroundColor Red; exit 1 }
Write-Host '[V74.0.84.1] Proven runtime target: main_menu RAD hard-gate freezes guest timeline.'
Write-Host '[V74.0.84.1] New route: PS Studios/attract remain RAD; logo_intro_loop/main_menu/main_menu_ngp use internal NIHAV composition.'
Write-Host '[V74.0.84.1] Guest UI HLE/CPU/GPU remains live for composited Binks.'
Write-Host "[V74.0.84.1] CurrentBaseBGRAChromaOrder=$order; target default=VU; opt-out env SHARPEMU_DS_UI_BINK_CHROMA_ORDER=uv"
Write-Host "[V74.0.84.1] HostSHA256=$(Sha $h)"
Write-Host "[V74.0.84.1] AssistSHA256=$(Sha $a)"
Write-Host "[V74.0.84.1] PresenterSHA256=$(Sha $p)"
Write-Host '[V74.0.84.1] PRECHECK PASSED.' -ForegroundColor Green
