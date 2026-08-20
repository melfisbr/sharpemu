. "$PSScriptRoot\common.ps1"
$repo=RepoRoot; $patches=Patches; $pkg=PackageRoot; $src=ImeDialogSource
$t=[IO.File]::ReadAllText($src)
if(-not $t.Contains('SHARPEMU_V74_0_85_IME_DIALOG_HOST_TEXT_INPUT')){ Write-Host '[V74.0.85][ERROR] TEST REFUSED: V74.0.85 source marker is not installed.' -ForegroundColor Red; exit 2 }
$eboot=$env:SHARPEMU_DEMONS_EBOOT
if([string]::IsNullOrWhiteSpace($eboot)){ $eboot='F:\JOGOSPS5\PPSA01341\eboot.bin' }
$exe=ExePath
if(-not(Test-Path -LiteralPath $exe)){ Write-Host "[V74.0.85][ERROR] executable missing: $exe" -ForegroundColor Red; exit 1 }
if(-not(Test-Path -LiteralPath $eboot)){ Write-Host "[V74.0.85][ERROR] eboot missing: $eboot" -ForegroundColor Red; exit 1 }
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ('SharpEmuV74085_stdout_'+$stamp+'.log')
$stderr=Join-Path $env:TEMP ('SharpEmuV74085_stderr_'+$stamp+'.log')
$runtime=Join-Path $patches ('SharpEmu_V74_0_85_IME_DIALOG_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_85_IME_DIALOG_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_85_IME_DIALOG_RESULT_'+$stamp+'.zip')
$env:SHARPEMU_IME_HOST_PANEL='1'
Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Write-Host ''
Write-Host '[V74.0.85] TESTE DO INPUT DE TEXTO:' -ForegroundColor Cyan
Write-Host '1. Percorra o boot normalmente ate Character Creation.'
Write-Host '2. Em Player Name, acione a edicao do nome.'
Write-Host '3. Deve abrir a janela "SharpEmu - Text Input".'
Write-Host '4. Digite DemonTest85 (ou outro nome) e pressione OK/ENTER.'
Write-Host '5. Confirme que o nome aparece no jogo e que Finalise permite continuar.'
Write-Host '6. Depois da evidencia, feche o SharpEmu normalmente.'
Write-Host ''
$arg='"'+$eboot.Replace('"','\"')+'"'
$proc=Start-Process -FilePath $exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$proc.WaitForExit(); $exitCode=$proc.ExitCode
$err=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''}; $out=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
$all=$err+"`r`n"+$out
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$lines=$all -split "`r?`n"
$init=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] init '})
$open=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] host_panel_open '})
$complete=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] host_panel_complete .*end_status=OK'})
$commit=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] text_commit '})
$finished=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] get_status .*status=FINISHED'})
$result=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] get_result .*end_status=OK'})
$term=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\] term '})
$error=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\].*(failed|error|retry)'})
$o=@('[V74.0.85] IME DIALOG RUNTIME RESULT')
$o+="ExitCode=$exitCode"
$o+="ime_init_count=$($init.Count)"; $o+="host_panel_open_count=$($open.Count)"; $o+="host_ok_count=$($complete.Count)"; $o+="text_commit_count=$($commit.Count)"; $o+="finished_status_count=$($finished.Count)"; $o+="ok_result_count=$($result.Count)"; $o+="term_count=$($term.Count)"; $o+="ime_error_count=$($error.Count)"
if($init.Count -gt 0 -and $open.Count -gt 0 -and $complete.Count -gt 0 -and $commit.Count -gt 0 -and $finished.Count -gt 0 -and $error.Count -eq 0){$o+='ime_verdict=HOST_TEXT_ENTRY_COMPLETED'}else{$o+='ime_verdict=INCOMPLETE_OR_NOT_OBSERVED'}
$o+='--- IME V74.0.85 lines ---'; $o+=@($lines|Where-Object{$_ -match '\[V74\.0\.85\]\[IME_DIALOG\]'}|Select-Object -First 500)
$o|Set-Content -LiteralPath $report -Encoding UTF8; $o|ForEach-Object{Write-Host $_}
$stage=Join-Path $env:TEMP ('SharpEmuV74085_'+$stamp); New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log'); Copy-Item $report (Join-Path $stage 'result.log'); Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_85_IME_DIALOG_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force; Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime"; Write-Host "ResultLog=$report"; Write-Host "RESULT ZIP=$zip"
