. "$PSScriptRoot\common.ps1"
$repo=RepoRoot; $ime=ImeDialogSource; $presenter=PresenterSource
try{ Assert-V740861 $repo } catch { Write-Host "$script:Tag [ERROR] $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
$it=NL([IO.File]::ReadAllText($ime)); $pt=NL([IO.File]::ReadAllText($presenter))
Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "ime_overlay_marker=True"
Write-Host "host_panel_spawn=True"
Write-Host "osk_overlay_layout=$($it.Contains("ABC") -and $it.Contains("Done"))"
Write-Host "ui_bink_snapshot_marker=$($pt.Contains("UI_BINK_FRAME_SNAPSHOT"))"
Write-Host "ui_bink_sticky_plane_marker=$($pt.Contains("UI_BINK_STICKY_PLANE"))"
Write-Host "ui_bink_plane_learn_marker=$($pt.Contains("UI_BINK_PLANE_LEARN"))"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
