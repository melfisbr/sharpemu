. "$PSScriptRoot\common.ps1"
$repo=RepoRoot; $patches=Patches; $pkg=PackageRoot; $p=Presenter
$ps=[IO.File]::ReadAllText($p)
if (-not ($ps.Contains('SHARPEMU_V74_0_84_2_UI_BINK_FRAME_OWNERSHIP') -and
          $ps.Contains('SHARPEMU_V74_0_84_2_UI_BINK_STICKY_PLANE_INTEGRITY'))) {
    Write-Host '[V74.0.84.2][ERROR] TEST REFUSED: V84.2 source markers are not installed.' -ForegroundColor Red
    exit 2
}
$eboot=$env:SHARPEMU_DEMONS_EBOOT
if ([string]::IsNullOrWhiteSpace($eboot)) { $eboot='F:\JOGOSPS5\PPSA01341\eboot.bin' }
$exe=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if (-not (Test-Path $exe)) { Write-Host "[V74.0.84.2][ERROR] build artifact missing: $exe" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $eboot)) { Write-Host "[V74.0.84.2][ERROR] eboot missing: $eboot" -ForegroundColor Red; exit 1 }
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ("SharpEmuV740842_stdout_"+$stamp+'.log')
$stderr=Join-Path $env:TEMP ("SharpEmuV740842_stderr_"+$stamp+'.log')
$runtime=Join-Path $patches ("SharpEmu_V74_0_84_2_UI_BINK_INTEGRITY_RUNTIME_"+$stamp+'.log')
$report=Join-Path $patches ("SharpEmu_V74_0_84_2_UI_BINK_INTEGRITY_RESULT_"+$stamp+'.log')
$zip=Join-Path $patches ("SharpEmu_V74_0_84_2_UI_BINK_INTEGRITY_RESULT_"+$stamp+'.zip')
$env:SHARPEMU_BINK_MODE='rad'
$env:SHARPEMU_BINK_ATTRACT_GUEST_COMPLETION='1'
$env:SHARPEMU_DS_UI_BINK_INTERNAL='1'
$env:SHARPEMU_DS_UI_BINK_CHROMA_ORDER='vu'
$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1'
Write-Host ''
Write-Host '[V74.0.84.2] TESTE:' -ForegroundColor Cyan
Write-Host '1. Deixe chegar ao attract e pressione TAB uma unica vez.'
Write-Host '2. Confirme que intro loop + PRESS ANY BUTTON continuam corretos.'
Write-Host '3. Entre no menu NEW GAME e NAO pressione TAB.'
Write-Host '4. Deixe main_menu.bk2 rodar pelo menos 20 segundos (ciclo completo de 600 frames).'
Write-Host '5. Se a imagem continuar correta, aguarde mais um ciclo; depois feche o SharpEmu.'
Write-Host ''
$arg='"'+$eboot.Replace('"','\"')+'"'
$proc=Start-Process -FilePath $exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$proc.WaitForExit(); $exitCode=$proc.ExitCode
$err=if (Test-Path $stderr) { [IO.File]::ReadAllText($stderr) } else { '' }
$out=if (Test-Path $stdout) { [IO.File]::ReadAllText($stdout) } else { '' }
$all=$err+"`r`n"+$out
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$lines=$all -split "`r?`n"
$snap=@($lines | Where-Object { $_ -match '\[V74\.0\.84\.2\]\[UI_BINK_FRAME_SNAPSHOT\].*main_menu(_ngp)?\.bk2' })
$learn=@($lines | Where-Object { $_ -match '\[V74\.0\.84\.2\]\[UI_BINK_PLANE_LEARN\].*main_menu(_ngp)?\.bk2' })
$sticky=@($lines | Where-Object { $_ -match '\[V74\.0\.84\.2\]\[UI_BINK_STICKY_PLANE\].*main_menu(_ngp)?\.bk2' })
$menuAttach=@($lines | Where-Object { $_ -match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2' })
$radMenu=@($lines | Where-Object { $_ -match 'Bink RAD bridge attached: main_menu(_ngp)?\.bk2' })
$hardMenu=@($lines | Where-Object { $_ -match 'rad_guest_hard_gate_started.*main_menu(_ngp)?\.bk2' })
$perf=@($lines | Where-Object { $_ -match "bink2\.perf file='main_menu(_ngp)?\.bk2'" })
$oom=@($lines | Where-Object { $_ -match 'OutOfDeviceMemory|vkAllocateMemory\(.*\) failed' })
$deviceLost=@($lines | Where-Object { $_ -match 'ErrorDeviceLost|deviceLost=True' })
$composite=@($lines | Where-Object { $_ -match '\[V74\.0\.81\]\[TITLE_LOOP_PRESS_COMPOSITE\].*main_menu(_ngp)?\.bk2' })
$o=@('[V74.0.84.2] RUNTIME RESULT')
$o+="ExitCode=$exitCode"
$o+="main_menu_nihav_attach_count=$($menuAttach.Count)"
$o+="main_menu_rad_attach_count=$($radMenu.Count)"
$o+="main_menu_hard_gate_count=$($hardMenu.Count)"
$o+="main_menu_frame_snapshot_trace_count=$($snap.Count)"
$o+="main_menu_plane_learn_trace_count=$($learn.Count)"
$o+="main_menu_sticky_plane_trace_count=$($sticky.Count)"
$o+="main_menu_composite_trace_count=$($composite.Count)"
$o+="main_menu_perf_trace_count=$($perf.Count)"
$o+="oom_count=$($oom.Count)"
$o+="device_lost_count=$($deviceLost.Count)"
if ($menuAttach.Count -gt 0 -and $radMenu.Count -eq 0 -and $hardMenu.Count -eq 0 -and $snap.Count -gt 0 -and $learn.Count -gt 0 -and $oom.Count -eq 0 -and $deviceLost.Count -eq 0) {
    $o+='integrity_path_verdict=ACTIVE_AND_GPU_HEALTHY'
} else {
    $o+='integrity_path_verdict=INCOMPLETE_OR_REGRESSED'
}
$o+='--- V84.2 / main-menu relevant lines ---'
$o+=@($lines | Where-Object { $_ -match 'V74\.0\.84\.2|V74\.0\.84\.1.*main_menu|TITLE_LOOP_PRESS_COMPOSITE.*main_menu|Bink2 NIHAV bridge attached: main_menu|Bink RAD bridge attached: main_menu|OutOfDeviceMemory|ErrorDeviceLost' } | Select-Object -First 800)
$o | Set-Content $report -Encoding UTF8
$o | ForEach-Object { Write-Host $_ }
$stage=Join-Path $env:TEMP ("SharpEmuV740842_"+$stamp)
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log')
Copy-Item $report (Join-Path $stage 'result.log')
Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latestBuild=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_84_2_UI_BINK_INTEGRITY_BUILD_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestBuild) { Copy-Item $latestBuild.FullName (Join-Path $stage 'build.log') }
Compress-Archive (Join-Path $stage '*') $zip -Force
Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime"
Write-Host "ResultLog=$report"
Write-Host "RESULT ZIP=$zip"
