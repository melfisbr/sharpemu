. "$PSScriptRoot\common.ps1"
$h=Host; $a=Assist; $p=Presenter; $patches=Patches
$hs=[IO.File]::ReadAllText($h); $as=[IO.File]::ReadAllText($a); $ps=[IO.File]::ReadAllText($p)
$o=@('[V74.0.84.1] DIAGNOSTIC START'); $bad=0
$checks=@(
    ,@('ui_bink_internal_routing',($hs.Contains('SHARPEMU_V74_0_84_1_UI_BINK_INTERNAL_ROUTING')))
    ,@('ui_bink_path_classifier',($hs.Contains('IsDemonSoulsUiBinkCompositePathV740841')))
    ,@('v81_compositor_generalized',($hs.Contains('return IsDemonSoulsUiBinkCompositePathV740841(_activePath) &&')))
    ,@('main_menu_passthrough',($as.Contains('SHARPEMU_V74_0_84_1_UI_BINK_GUEST_LIVE_PASSTHROUGH') -and $as.Contains('main_menu.bk2') -and $as.Contains('main_menu_ngp.bk2')))
    ,@('guest_chroma_contract',($ps.Contains('SHARPEMU_V74_0_84_1_UI_BINK_GUEST_CHROMA_ORDER')))
    ,@('chroma_normalize_call',($ps.Contains('NormalizeDemonSoulsUiBinkChromaV740841(')))
    ,@('v772_completion_preserved',($hs.Contains('SHARPEMU_V74_0_77_2_DEMONS_ATTRACT_GUEST_COMPLETION')))
    ,@('v83_stale_reset_preserved',($ps.Contains('SHARPEMU_V74_0_83_ACTIVE_MOVIE_RECONCILE')))
    ,@('build_artifact_exists',(Test-Path (Join-Path (RepoRoot) 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe')))
)
foreach ($c in $checks) { $o+="$($c[0])=$($c[1])"; if (-not $c[1]) { $bad++ } }
try { $o+="base_chroma_order=$(GetBaseChromaOrder $ps)" } catch { $o+="base_chroma_order=ERROR:$($_.Exception.Message)"; $bad++ }
$o+="HostSHA256=$(Sha $h)"; $o+="AssistSHA256=$(Sha $a)"; $o+="PresenterSHA256=$(Sha $p)"
if ($bad) { $o+="[V74.0.84.1] DIAGNOSTIC FAILED issues=$bad" } else { $o+='[V74.0.84.1] DIAGNOSTIC PASSED.' }
$o | ForEach-Object { Write-Host $_ }
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stage=Join-Path $env:TEMP ("SharpEmuV740841Diag_"+$stamp)
New-Item -ItemType Directory -Force $stage | Out-Null
$o | Set-Content (Join-Path $stage 'diagnostic.log') -Encoding UTF8
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_84_1_UI_BINK_COLOR_SYNC_BUILD_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) { Copy-Item $latest.FullName (Join-Path $stage 'build.log') }
$z=Join-Path $patches ("SharpEmu_V74_0_84_1_UI_BINK_COLOR_SYNC_DIAGNOSTIC_RESULT_"+$stamp+'.zip')
Compress-Archive (Join-Path $stage '*') $z -Force
Remove-Item $stage -Recurse -Force
Write-Host "RESULT ZIP: $z"
if ($bad) { exit 1 }
