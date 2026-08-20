. "$PSScriptRoot\common.ps1"
$repo=RepoRoot;$patches=Patches;$pkg=PackageRoot
$eboot=$env:SHARPEMU_DEMONS_EBOOT;if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
$exe=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if(-not(Test-Path $exe)){Write-Host "[V74.0.84][ERROR] build artifact missing: $exe" -ForegroundColor Red;exit 1}
if(-not(Test-Path $eboot)){Write-Host "[V74.0.84][ERROR] eboot missing: $eboot" -ForegroundColor Red;exit 1}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ("SharpEmuV74084_stdout_"+$stamp+'.log');$stderr=Join-Path $env:TEMP ("SharpEmuV74084_stderr_"+$stamp+'.log')
$runtime=Join-Path $patches ("SharpEmu_V74_0_84_UI_BINK_COLOR_SYNC_RUNTIME_"+$stamp+'.log')
$report=Join-Path $patches ("SharpEmu_V74_0_84_UI_BINK_COLOR_SYNC_RESULT_"+$stamp+'.log')
$zip=Join-Path $patches ("SharpEmu_V74_0_84_UI_BINK_COLOR_SYNC_RESULT_"+$stamp+'.zip')
$env:SHARPEMU_BINK_MODE='rad'
$env:SHARPEMU_BINK_ATTRACT_GUEST_COMPLETION='1'
$env:SHARPEMU_DS_UI_BINK_INTERNAL='1'
$env:SHARPEMU_DS_UI_BINK_CHROMA_ORDER='vu'
Write-Host ''
Write-Host '[V74.0.84] TESTE MANUAL COMPLETO:' -ForegroundColor Cyan
Write-Host '1. Deixe PS Studios/attract executarem normalmente pelo RAD.'
Write-Host '2. No attract, pressione TAB uma unica vez para pular.'
Write-Host '3. Confirme logo_intro -> logo_intro_loop -> PRESS ANY BUTTON.'
Write-Host '4. Entre no menu inicial e deixe o fundo + UI animarem por pelo menos 10 segundos.'
Write-Host '5. Feche o SharpEmu para gerar o relatorio/ZIP.'
Write-Host ''
# Windows PowerShell 5.1 compatible: Start-Process -ArgumentList, never ProcessStartInfo.ArgumentList.
$arg='"'+$eboot.Replace('"','\"')+'"'
$p=Start-Process -FilePath $exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$p.WaitForExit();$exitCode=$p.ExitCode
$err=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''};$out=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
$all=$err+"`r`n"+$out;[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$lines=$all -split "`r?`n"
$internalLoop=@($lines|Where-Object{$_ -match '\[V74\.0\.84\]\[UI_BINK_INTERNAL\].*logo_intro_loop\.bk2'})
$internalMenu=@($lines|Where-Object{$_ -match '\[V74\.0\.84\]\[UI_BINK_INTERNAL\].*main_menu(_ngp)?\.bk2'})
$radMenu=@($lines|Where-Object{$_ -match 'Bink RAD bridge attached: main_menu(_ngp)?\.bk2'})
$hardMenu=@($lines|Where-Object{$_ -match 'rad_guest_hard_gate_started.*main_menu(_ngp)?\.bk2'})
$nihavMenu=@($lines|Where-Object{$_ -match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2'})
$chromaLoop=@($lines|Where-Object{$_ -match '\[V74\.0\.84\]\[UI_BINK_CHROMA\].*logo_intro_loop\.bk2'})
$chromaMenu=@($lines|Where-Object{$_ -match '\[V74\.0\.84\]\[UI_BINK_CHROMA\].*main_menu(_ngp)?\.bk2'})
$loopComposite=@($lines|Where-Object{$_ -match '\[V74\.0\.81\]\[TITLE_LOOP_PRESS_COMPOSITE\].*logo_intro_loop\.bk2'})
$menuComposite=@($lines|Where-Object{$_ -match '\[V74\.0\.81\]\[TITLE_LOOP_PRESS_COMPOSITE\].*main_menu(_ngp)?\.bk2'})
$menuIdx=-1;for($i=0;$i-lt$lines.Length;$i++){if($lines[$i]-match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2'){$menuIdx=$i;break}}
$postMenu=if($menuIdx-ge 0-and$menuIdx+1-lt$lines.Length){$lines[($menuIdx+1)..($lines.Length-1)]}else{@()}
$guestWork=@($postMenu|Where-Object{$_ -match '\[GATE_OWNER_WAIT_DRAIN\]'})
$timeline=@();foreach($l in $postMenu){if($l -match 'timeline=(\d+)/(\d+)'){$timeline+=$matches[1]}}
$distinctTimeline=@($timeline|Select-Object -Unique)
$o=@('[V74.0.84] RUNTIME RESULT')
$o+="ExitCode=$exitCode";$o+="ui_internal_logo_loop_count=$($internalLoop.Count)";$o+="ui_internal_main_menu_count=$($internalMenu.Count)";$o+="rad_main_menu_attach_count=$($radMenu.Count)";$o+="rad_main_menu_hard_gate_count=$($hardMenu.Count)";$o+="nihav_main_menu_attach_count=$($nihavMenu.Count)";$o+="chroma_logo_loop_count=$($chromaLoop.Count)";$o+="chroma_main_menu_count=$($chromaMenu.Count)";$o+="logo_loop_composite_count=$($loopComposite.Count)";$o+="main_menu_composite_count=$($menuComposite.Count)";$o+="post_main_menu_guest_work_count=$($guestWork.Count)";$o+="post_main_menu_distinct_timeline_count=$($distinctTimeline.Count)"
if($internalMenu.Count-gt 0-and$radMenu.Count-eq 0-and$hardMenu.Count-eq 0-and$nihavMenu.Count-gt 0-and$guestWork.Count-gt 0){$o+='sync_verdict=PASS_MAIN_MENU_GUEST_REMAINS_LIVE'}elseif($internalMenu.Count-eq 0){$o+='sync_verdict=FAIL_MAIN_MENU_NOT_INTERNAL'}elseif($hardMenu.Count-gt 0-or$radMenu.Count-gt 0){$o+='sync_verdict=FAIL_RAD_GATE_STILL_OWNS_MAIN_MENU'}else{$o+='sync_verdict=INCOMPLETE_CLOSE_AFTER_MENU_FOR_MORE_EVIDENCE'}
if($chromaLoop.Count-gt 0-or$chromaMenu.Count-gt 0){$o+='color_contract=VU_ACTIVE'}else{$o+='color_contract=NOT_OBSERVED'}
$o+='--- relevant UI Bink lines ---';$o+=@($lines|Where-Object{$_ -match 'V74\.0\.84|TITLE_LOOP_PRESS_COMPOSITE|Bink2 NIHAV bridge attached: (logo_intro_loop|main_menu)|Bink RAD bridge attached: main_menu|rad_guest_hard_gate_started.*main_menu' }|Select-Object -First 500)
$o|Set-Content $report -Encoding UTF8;$o|ForEach-Object{Write-Host $_}
$stage=Join-Path $env:TEMP ("SharpEmuV74084_"+$stamp);New-Item -ItemType Directory -Force $stage|Out-Null;Copy-Item $runtime (Join-Path $stage 'runtime.log');Copy-Item $report (Join-Path $stage 'result.log');Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latestBuild=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_84_UI_BINK_COLOR_SYNC_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($latestBuild){Copy-Item $latestBuild.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force;Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime";Write-Host "ResultLog=$report";Write-Host "RESULT ZIP=$zip"
