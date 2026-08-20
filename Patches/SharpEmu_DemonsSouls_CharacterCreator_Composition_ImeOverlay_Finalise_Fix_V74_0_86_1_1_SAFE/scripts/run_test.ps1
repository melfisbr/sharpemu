. "$PSScriptRoot\common.ps1"
$repo=RepoRoot;$patches=Patches;$pkg=PackageRoot
$it=NL([IO.File]::ReadAllText((ImeDialogSource)));$pt=NL([IO.File]::ReadAllText((PresenterSource))
if(-not$it.Contains('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY') -or -not$pt.Contains('SHARPEMU_V74_0_86_1_1_UI_BINK_DISCOVERY_REMEMBER')){Write-Host "$script:Tag [ERROR] TEST REFUSED: V74.0.86.1.1 markers are not installed." -ForegroundColor Red;exit 2}
$eboot=$env:SHARPEMU_DEMONS_EBOOT;if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
$exe=ExePath
if(-not(Test-Path -LiteralPath $exe)){Write-Host "$script:Tag [ERROR] executable missing: $exe" -ForegroundColor Red;exit 1}
if(-not(Test-Path -LiteralPath $eboot)){Write-Host "$script:Tag [ERROR] eboot missing: $eboot" -ForegroundColor Red;exit 1}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ('SharpEmuV7408611_stdout_'+$stamp+'.log');$stderr=Join-Path $env:TEMP ('SharpEmuV7408611_stderr_'+$stamp+'.log')
$runtime=Join-Path $patches ('SharpEmu_V74_0_86_1_1_CHARACTER_CREATOR_UI_BINK_IME_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_86_1_1_CHARACTER_CREATOR_UI_BINK_IME_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_86_1_1_CHARACTER_CREATOR_UI_BINK_IME_RESULT_'+$stamp+'.zip')
$env:SHARPEMU_IME_HOST_PANEL='1';$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1';$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1'
Write-Host ''
Write-Host "$script:Tag TESTE:" -ForegroundColor Cyan
Write-Host '1. Chegue ao NEW GAME / Character Creation.'
Write-Host '2. Observe o fundo Bink, HUD e se o modelo 3D do personagem aparece.'
Write-Host '3. Abra Player Name; use o novo OSK e confirme em Done.'
Write-Host '4. Pressione Finalise e aguarde a tela seguinte por pelo menos 10 segundos.'
Write-Host '5. Feche o SharpEmu normalmente se ele permanecer aberto.'
Write-Host ''
$arg='"'+$eboot.Replace('"','\"')+'"'
$proc=Start-Process -FilePath $exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$proc.WaitForExit();$exitCode=$proc.ExitCode
$stderrText=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''};$stdoutText=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''};$all=$stderrText+"`r`n"+$stdoutText
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$lines=$all -split "`r?`n"
$ime=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\] text_commit '})
$snap=@($lines|Where-Object{$_ -match '\[V74\.0\.84\.2\.1\]\[UI_BINK_FRAME_SNAPSHOT\]'})
$learn=@($lines|Where-Object{$_ -match '\[V74\.0\.84\.2\.1\]\[UI_BINK_PLANE_LEARN\]'})
$sticky=@($lines|Where-Object{$_ -match '\[V74\.0\.84\.2\.1\]\[UI_BINK_STICKY_PLANE\]'})
$av=@($lines|Where-Object{$_ -match 'ACCESS_VIOLATION|Type: Access Violation|VEH_AV first-chance'})
$o=@("$script:Tag RUNTIME RESULT")
$o+="ExitCode=$exitCode"
$o+="ime_text_commit_count=$($ime.Count)"
$o+="ui_bink_frame_snapshot_count=$($snap.Count)"
$o+="ui_bink_plane_learn_count=$($learn.Count)"
$o+="ui_bink_sticky_plane_count=$($sticky.Count)"
$o+="access_violation_count=$($av.Count)"
if($learn.Count -gt 0){$o+='ui_bink_learning_verdict=PASS'}else{$o+='ui_bink_learning_verdict=NOT_OBSERVED'}
if($av.Count -eq 0){$o+='finalise_verdict=NO_ACCESS_VIOLATION_OBSERVED'}else{$o+='finalise_verdict=ACCESS_VIOLATION_STILL_PRESENT'}
$o+='--- IME ---';$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.86\.1\]\[IME_DIALOG\]'}|Select-Object -First 300)
$o+='--- UI BINK ---';$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.84\.2\.1\]\[UI_BINK_'}|Select-Object -First 500)
$o+='--- CRASH ---';$o+=@($lines|Where-Object{$_ -match 'ACCESS_VIOLATION|Type: Access Violation|VEH_AV first-chance'}|Select-Object -First 200)
$o|Set-Content -LiteralPath $report -Encoding UTF8;$o|ForEach-Object{Write-Host $_}
$stage=Join-Path $env:TEMP ('SharpEmuV7408611_'+$stamp);New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log');Copy-Item $report (Join-Path $stage 'result.log');Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_86_1_1_CHARACTER_CREATOR_UI_BINK_IME_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force;Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime";Write-Host "ResultLog=$report";Write-Host "RESULT ZIP=$zip"
