. "$PSScriptRoot\common.ps1"
$repo=RepoRoot; $patches=Patches; $pkg=PackageRoot
$it=[IO.File]::ReadAllText((ImeDialogSource));$pt=[IO.File]::ReadAllText((PresenterSource))
if(-not$it.Contains('SHARPEMU_V74_0_86_IME_VISIBLE_HOST_TEXT_INPUT') -or -not$pt.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')){Write-Host "$script:Tag [ERROR] TEST REFUSED: V74.0.86 source markers are not installed." -ForegroundColor Red;exit 2}
$eboot=$env:SHARPEMU_DEMONS_EBOOT;if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
$exe=ExePath
if(-not(Test-Path -LiteralPath $exe)){Write-Host "$script:Tag [ERROR] executable missing: $exe" -ForegroundColor Red;exit 1}
if(-not(Test-Path -LiteralPath $eboot)){Write-Host "$script:Tag [ERROR] eboot missing: $eboot" -ForegroundColor Red;exit 1}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ('SharpEmuV74086_stdout_'+$stamp+'.log');$stderr=Join-Path $env:TEMP ('SharpEmuV74086_stderr_'+$stamp+'.log')
$runtime=Join-Path $patches ('SharpEmu_V74_0_86_CHARACTER_CREATOR_UI_IME_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_86_CHARACTER_CREATOR_UI_IME_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_86_CHARACTER_CREATOR_UI_IME_RESULT_'+$stamp+'.zip')
$env:SHARPEMU_IME_HOST_PANEL='1';$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1';Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "$script:Tag TESTE CHARACTER CREATOR / IME:" -ForegroundColor Cyan
Write-Host '1. Percorra o boot ate Character Creation e observe Body Type / Foundation / Appearance.'
Write-Host '2. Em Player Name, acione a edicao. A janela "SharpEmu - Text Input" deve ficar visivel por cima do jogo.'
Write-Host '3. Digite DemonTest86 e pressione OK/ENTER.'
Write-Host '4. Confirme o nome no jogo e tente Finalise.'
Write-Host '5. Deixe a proxima tela renderizar alguns segundos e feche o SharpEmu normalmente.'
Write-Host ''
$arg='"'+$eboot.Replace('"','\"')+'"'
$proc=Start-Process -FilePath $exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$proc.WaitForExit();$exitCode=$proc.ExitCode
$stderrText=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''};$stdoutText=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''};$all=$stderrText+"`r`n"+$stdoutText
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$lines=$all -split "`r?`n"
$imeInit=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] init '})
$imeOpen=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] host_panel_open '})
$imeSpawn=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] host_panel_spawn '})
$imeComplete=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] host_panel_complete .*end_status=OK'})
$imeCommit=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] text_commit '})
$imeFinished=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] get_status .*status=FINISHED'})
$imeResult=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] get_result .*end_status=OK'})
$imeTerm=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\] term '})
$imeErrors=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\].*(failed|error|retry)'})
$dccReject=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[DS_DCC_TYPED_REJECT\]'})
$dccReplacement=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[DS_DCC_EXACT_REPLACEMENT\]'})
$rgba8Wrong=@($lines|Where-Object{$_ -match 'DCC_META_ALIAS.*action=hit.*sample_fmt=R8G8B8A8Unorm.*image_fmt=R16G16Sfloat'})
$r32g32Wrong=@($lines|Where-Object{$_ -match 'DCC_META_ALIAS.*action=hit.*sample_fmt=R32G32Uint.*image_fmt=R16G16B16A16Sfloat'})
$dlssActive=@($lines|Where-Object{$_ -match 'UPSCALER\]\[PRECOMPOSITE\] requested=dlss selected=dlss state=active'})
$o=@("$script:Tag CHARACTER CREATOR UI / IME RUNTIME RESULT")
$o+="ExitCode=$exitCode"
$o+="ime_init_count=$($imeInit.Count)";$o+="host_panel_open_count=$($imeOpen.Count)";$o+="host_panel_spawn_count=$($imeSpawn.Count)";$o+="host_ok_count=$($imeComplete.Count)";$o+="text_commit_count=$($imeCommit.Count)";$o+="finished_status_count=$($imeFinished.Count)";$o+="ok_result_count=$($imeResult.Count)";$o+="term_count=$($imeTerm.Count)";$o+="ime_error_count=$($imeErrors.Count)"
$o+="ds_dcc_typed_reject_count=$($dccReject.Count)";$o+="ds_dcc_exact_replacement_count=$($dccReplacement.Count)";$o+="rgba8_as_rg16f_hit_count=$($rgba8Wrong.Count)";$o+="r32g32ui_as_rgba16f_hit_count=$($r32g32Wrong.Count)";$o+="dlss_active_count=$($dlssActive.Count)"
if($imeInit.Count -gt 0 -and $imeSpawn.Count -gt 0 -and $imeComplete.Count -gt 0 -and $imeCommit.Count -gt 0 -and $imeFinished.Count -gt 0 -and $imeErrors.Count -eq 0){$o+='ime_verdict=HOST_TEXT_ENTRY_COMPLETED'}else{$o+='ime_verdict=INCOMPLETE_OR_NOT_OBSERVED'}
if($rgba8Wrong.Count -eq 0 -and $r32g32Wrong.Count -eq 0){$o+='typed_dcc_verdict=NO_KNOWN_CROSS_FORMAT_HITS'}else{$o+='typed_dcc_verdict=CROSS_FORMAT_HITS_REMAIN'}
$o+='--- V74.0.86 IME lines ---';$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[IME_DIALOG\]'}|Select-Object -First 500)
$o+='--- V74.0.86 DCC lines ---';$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.86\]\[DS_DCC_'}|Select-Object -First 500)
$o+='--- Remaining known mismatched DCC hits ---';$o+=@($rgba8Wrong|Select-Object -First 100);$o+=@($r32g32Wrong|Select-Object -First 100)
$o|Set-Content -LiteralPath $report -Encoding UTF8;$o|ForEach-Object{Write-Host $_}
$stage=Join-Path $env:TEMP ('SharpEmuV74086_'+$stamp);New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log');Copy-Item $report (Join-Path $stage 'result.log');Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_86_CHARACTER_CREATOR_UI_IME_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force;Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime";Write-Host "ResultLog=$report";Write-Host "RESULT ZIP=$zip"
