. "$PSScriptRoot\common.ps1"
$repo=RepoRoot; $patches=Patches; $pkg=PackageRoot
$it=[IO.File]::ReadAllText((ImeDialogSource));$pt=[IO.File]::ReadAllText((PresenterSource))
if(-not$it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY') -or -not$pt.Contains('SHARPEMU_V74_0_86_1_DS_UI_BINK_CHARACTER_CREATOR_COMPOSITE')){Write-Host "$script:Tag [ERROR] TEST REFUSED: V74.0.86.1 source markers are not installed." -ForegroundColor Red;exit 2}
$eboot=$env:SHARPEMU_DEMONS_EBOOT;if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
$exe=ExePath
if(-not(Test-Path -LiteralPath $exe)){Write-Host "$script:Tag [ERROR] executable missing: $exe" -ForegroundColor Red;exit 1}
if(-not(Test-Path -LiteralPath $eboot)){Write-Host "$script:Tag [ERROR] eboot missing: $eboot" -ForegroundColor Red;exit 1}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ('SharpEmuV740861_stdout_'+$stamp+'.log');$stderr=Join-Path $env:TEMP ('SharpEmuV740861_stderr_'+$stamp+'.log')
$runtime=Join-Path $patches ('SharpEmu_V74_0_86_1_CHARACTER_CREATOR_UI_COMPOSITE_IME_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_86_1_CHARACTER_CREATOR_UI_COMPOSITE_IME_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_86_1_CHARACTER_CREATOR_UI_COMPOSITE_IME_RESULT_'+$stamp+'.zip')
$env:SHARPEMU_IME_HOST_PANEL='1';$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1';$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1';Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "$script:Tag TESTE CHARACTER CREATOR / UI / IME:" -ForegroundColor Cyan
Write-Host '1. Percorra o boot ate a tela NEW GAME.'
Write-Host '2. Verifique se o background/armadura do Character Creation aparece sem tela verde/magenta.'
Write-Host '3. Em Player Name, acione a edicao. Deve abrir um teclado on-screen maior, estilo overlay.'
Write-Host '4. Digite DemonTest861 e pressione Done/OK.'
Write-Host '5. Tente Finalise e aguarde a proxima tela por alguns segundos.'
Write-Host ''
$arg='"'+$eboot.Replace('"','\"')+'"'
$proc=Start-Process -FilePath $exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$proc.WaitForExit();$exitCode=$proc.ExitCode
$stderrText=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''};$stdoutText=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''};$all=$stderrText+"`r`n"+$stdoutText
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$lines=$all -split "`r?`n"
$imeInit=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\] init '})
$imeComplete=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\] host_panel_complete .*end_status=OK'})
$imeCommit=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\] text_commit '})
$imeResult=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\] get_result .*end_status=OK'})
$uiSnap=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[UI_BINK_FRAME_SNAPSHOT\]'})
$uiLearn=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[UI_BINK_PLANE_LEARN\]'})
$uiSticky=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[UI_BINK_STICKY_PLANE\]'})
$accessViolation=@($lines|Where-Object{$_ -match 'Access Violation|ACCESS_VIOLATION|VEH_AV first-chance'})
$o=@("$script:Tag CHARACTER CREATOR UI / IME RUNTIME RESULT")
$o+="ExitCode=$exitCode"
$o+="ime_init_count=$($imeInit.Count)"
$o+="ime_ok_count=$($imeComplete.Count)"
$o+="text_commit_count=$($imeCommit.Count)"
$o+="ok_result_count=$($imeResult.Count)"
$o+="ui_bink_snapshot_count=$($uiSnap.Count)"
$o+="ui_bink_plane_learn_count=$($uiLearn.Count)"
$o+="ui_bink_sticky_plane_count=$($uiSticky.Count)"
$o+="access_violation_count=$($accessViolation.Count)"
if($imeInit.Count -gt 0 -and $imeCommit.Count -gt 0){$o+='ime_verdict=HOST_OSK_COMPLETED'}else{$o+='ime_verdict=IME_NOT_COMPLETED'}
if($uiSnap.Count -gt 0 -and ($uiLearn.Count -gt 0 -or $uiSticky.Count -gt 0)){$o+='ui_composite_verdict=HOST_UI_BINK_GUARDED'}else{$o+='ui_composite_verdict=UNCONFIRMED'}
if($accessViolation.Count -eq 0){$o+='finalise_crash_verdict=NO_ACCESS_VIOLATION_OBSERVED'}else{$o+='finalise_crash_verdict=ACCESS_VIOLATION_STILL_PRESENT'}
$o+='--- V74.0.86.1 IME lines ---';$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\]'}|Select-Object -First 500)
$o+='--- V74.0.86.1 UI Bink lines ---';$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[UI_BINK_'}|Select-Object -First 500)
$o+='--- Crash lines ---';$o+=@($accessViolation|Select-Object -First 200)
$o|Set-Content -LiteralPath $report -Encoding UTF8;$o|ForEach-Object{Write-Host $_}
$stage=Join-Path $env:TEMP ('SharpEmuV740861_'+$stamp);New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log');Copy-Item $report (Join-Path $stage 'result.log');Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_86_1_CHARACTER_CREATOR_UI_COMPOSITE_IME_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force;Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime";Write-Host "ResultLog=$report";Write-Host "RESULT ZIP=$zip"
