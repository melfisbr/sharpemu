. "$PSScriptRoot\common.ps1"
$p=Paths
$patches=Patches
$pkg=PackageRoot

try{Assert-V74088 $p.Repo}catch{
    Write-Host "$script:Tag [ERROR] TEST REFUSED: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$eboot=$env:SHARPEMU_DEMONS_EBOOT
if([string]::IsNullOrWhiteSpace($eboot)){
    $eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
}
if(-not(Test-Path -LiteralPath $p.Exe)){
    Write-Host "$script:Tag [ERROR] executable missing: $($p.Exe)" -ForegroundColor Red
    exit 1
}
if(-not(Test-Path -LiteralPath $eboot)){
    Write-Host "$script:Tag [ERROR] eboot missing: $eboot" -ForegroundColor Red
    exit 1
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue

$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stdout=Join-Path $env:TEMP ('SharpEmuV74088_stdout_'+$stamp+'.log')
$stderr=Join-Path $env:TEMP ('SharpEmuV74088_stderr_'+$stamp+'.log')
$runtime=Join-Path $patches ('SharpEmu_V74_0_88_INWINDOW_IME_UI_BINK_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_88_INWINDOW_IME_UI_BINK_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_88_INWINDOW_IME_UI_BINK_RESULT_'+$stamp+'.zip')

$env:SHARPEMU_DS_UI_BINK_INTERNAL='1'
$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1'
$env:SHARPEMU_DS_UI_BINK_LOOP='1'
$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1'
Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_IME_HOST_PANEL -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "$script:Tag TESTE DEMON'S SOULS:" -ForegroundColor Cyan
Write-Host '1. Percorra o boot ate NEW GAME e permaneça nessa tela por pelo menos 30 segundos.'
Write-Host '2. O main_menu.bk2 deve continuar animado depois de 20 segundos, sem fundo verde/magenta.'
Write-Host '3. Entre em Character Creation e confirme se o modelo 3D aparece.'
Write-Host '4. Em Player Name, o teclado deve aparecer DENTRO da janela do SharpEmu.'
Write-Host '5. Teclado: digite normalmente; Enter=Done, Esc=Cancel, Backspace=apagar.'
Write-Host '6. Controle: D-pad navega, X seleciona, Quadrado apaga, Circulo cancela, Options conclui.'
Write-Host '7. Digite Demon88, conclua e tente Finalise.'
Write-Host '8. Se o jogo continuar, aguarde ao menos 10 segundos e feche normalmente.'
Write-Host ''

$arg='"'+$eboot.Replace('"','\"')+'"'
$proc=Start-Process -FilePath $p.Exe -ArgumentList $arg -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$proc.WaitForExit()
$exitCode=$proc.ExitCode

$err=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''}
$out=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
$all=$err+"`r`n"+$out
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue

$lines=$all -split "`r?`n"
$imeOpen=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_IN_WINDOW\] open '})
$imeResult=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_IN_WINDOW\] result '})
$imeCommit=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_DIALOG\] text_commit '})
$external=@($lines|Where-Object{$_ -match 'host_panel_spawn|windows-powershell-winforms|powershell\.exe'})
$uintBind=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[UI_BINK_UINT_PLANE_BIND\]'})
$loop=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[UI_BINK_LOOP_RESTART\].*result=rewound'})
$yuvMiss=@($lines|Where-Object{$_ -match 'bink2\.yuv_pair_not_found.*main_menu'})
$accessViolation=@($lines|Where-Object{$_ -match 'ACCESS_VIOLATION|Type: Access Violation|VEH_AV first-chance'})
$mainMenuAttach=@($lines|Where-Object{$_ -match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2'})

$o=@()
$o+="$script:Tag RUNTIME RESULT"
$o+="ExitCode=$exitCode"
$o+="ime_in_window_open_count=$($imeOpen.Count)"
$o+="ime_in_window_result_count=$($imeResult.Count)"
$o+="ime_text_commit_count=$($imeCommit.Count)"
$o+="external_ime_process_count=$($external.Count)"
$o+="ui_bink_uint_plane_bind_count=$($uintBind.Count)"
$o+="ui_bink_loop_restart_count=$($loop.Count)"
$o+="main_menu_nihav_attach_count=$($mainMenuAttach.Count)"
$o+="main_menu_yuv_pair_miss_count=$($yuvMiss.Count)"
$o+="access_violation_count=$($accessViolation.Count)"

if($imeOpen.Count -gt 0 -and $imeCommit.Count -gt 0 -and $external.Count -eq 0){
    $o+='ime_verdict=IN_WINDOW_SYSTEM_IME_COMPLETED'
}else{
    $o+='ime_verdict=IN_WINDOW_IME_INCOMPLETE'
}
if($uintBind.Count -gt 0){
    $o+='bink_plane_verdict=UINT_YUV_HOST_SUBSTITUTION_ACTIVE'
}else{
    $o+='bink_plane_verdict=UINT_YUV_BIND_NOT_OBSERVED'
}
if($loop.Count -gt 0){
    $o+='bink_loop_verdict=MAIN_MENU_LOOP_REWOUND_WITHOUT_GUEST_CLOSE'
}else{
    $o+='bink_loop_verdict=LOOP_RESTART_NOT_OBSERVED'
}
if($accessViolation.Count -eq 0){
    $o+='finalise_verdict=NO_ACCESS_VIOLATION_OBSERVED'
}else{
    $o+='finalise_verdict=ACCESS_VIOLATION_STILL_PRESENT'
}

$o+='--- V74.0.88 IME ---'
$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[(IME_IN_WINDOW|IME_DIALOG)\]'}|Select-Object -First 500)
$o+='--- V74.0.88 UI BINK ---'
$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[UI_BINK_'}|Select-Object -First 800)
$o+='--- main_menu Bink diagnostics ---'
$o+=@($lines|Where-Object{$_ -match 'main_menu(_ngp)?\.bk2|bink2\.yuv_pair_not_found'}|Select-Object -First 800)
$o+='--- Crash ---'
$o+=@($accessViolation|Select-Object -First 300)

$o|Set-Content -LiteralPath $report -Encoding UTF8
$o|ForEach-Object{Write-Host $_}

$stage=Join-Path $env:TEMP ('SharpEmuV74088_'+$stamp)
New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log')
Copy-Item $report (Join-Path $stage 'result.log')
Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_88_INWINDOW_IME_UI_BINK_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force
Remove-Item $stage -Recurse -Force

Write-Host "RuntimeLog=$runtime"
Write-Host "ResultLog=$report"
Write-Host "RESULT ZIP=$zip"
