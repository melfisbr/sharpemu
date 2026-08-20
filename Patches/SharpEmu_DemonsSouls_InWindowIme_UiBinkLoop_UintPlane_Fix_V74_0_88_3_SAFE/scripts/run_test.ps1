. "$PSScriptRoot\common.ps1"
$p=Paths
$patches=Patches
$pkg=PackageRoot

try{
    Assert-V740883 $p.Repo
}
catch{
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
$runtime=Join-Path $patches ('SharpEmu_V74_0_88_3_POST_INTRO_LIVE_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_88_3_POST_INTRO_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_88_3_POST_INTRO_RESULT_'+$stamp+'.zip')

$env:SHARPEMU_DS_UI_BINK_INTERNAL='1'
$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1'
$env:SHARPEMU_DS_UI_BINK_LOOP='1'
$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1'
Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_IME_HOST_PANEL -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "$script:Tag TESTE:" -ForegroundColor Cyan
Write-Host '1. Percorra o boot normalmente depois da intro.'
Write-Host '2. Se chegar em NEW GAME, permaneça por pelo menos 30 segundos.'
Write-Host '3. Entre em Character Creation e teste o IME dentro da janela.'
Write-Host '4. Se o emulador travar, feche a janela do SharpEmu. O log ja esta sendo salvo ao vivo em Patches.'
Write-Host ''
Write-Host "$script:Tag LIVE_RUNTIME_LOG=$runtime" -ForegroundColor Yellow
Write-Host ''

# LIVE_RUNTIME_LOG: no temporary stdout/stderr files are used.
# Every native output line is flushed directly to the final Patches runtime log,
# eliminating the V88.2 ReadAllText/file-lock race.
$utf8=New-Object Text.UTF8Encoding($false)
$writer=New-Object IO.StreamWriter($runtime,$false,$utf8)
$writer.AutoFlush=$true
$exitCode=-1

try{
    & $p.Exe $eboot 2>&1 | ForEach-Object {
        $line=[string]$_
        $writer.WriteLine($line)

        # Keep the console useful without echoing the full high-volume trace.
        if($line -match '\[V74\.0\.88(\.3)?\]' -or
           $line -match 'ACCESS_VIOLATION|Type: Access Violation|DEVICE_LOST|Unhandled|Fatal'){
            Write-Host $line
        }
    }
    $exitCode=$LASTEXITCODE
}
finally{
    $writer.Flush()
    $writer.Dispose()
}

$all=if(Test-Path -LiteralPath $runtime){
    [IO.File]::ReadAllText($runtime)
}else{
    ''
}
$lines=$all -split "`r?`n"

$imeOpen=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_IN_WINDOW\] open '})
$imeCommit=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_DIALOG\] text_commit '})
$uintBind=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[UI_BINK_UINT_PLANE_BIND\]'})
$mainLoop=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.3\]\[MAIN_MENU_LOOP_RESTART\].*result=rewound'})
$introLoop=@($lines|Where-Object{$_ -match '\[V74\.0\.88(\.3)?\]\[(UI_BINK_LOOP_RESTART|MAIN_MENU_LOOP_RESTART)\].*logo_intro_loop'})
$mainAttach=@($lines|Where-Object{$_ -match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2'})
$accessViolation=@($lines|Where-Object{$_ -match 'ACCESS_VIOLATION|Type: Access Violation|VEH_AV first-chance'})

$o=@()
$o+="$script:Tag RUNTIME RESULT"
$o+="ExitCode=$exitCode"
$o+="ime_in_window_open_count=$($imeOpen.Count)"
$o+="ime_text_commit_count=$($imeCommit.Count)"
$o+="ui_bink_uint_plane_bind_count=$($uintBind.Count)"
$o+="main_menu_loop_restart_count=$($mainLoop.Count)"
$o+="logo_intro_loop_restart_count=$($introLoop.Count)"
$o+="main_menu_attach_count=$($mainAttach.Count)"
$o+="access_violation_count=$($accessViolation.Count)"
$o+="runtime_log_bytes=$((Get-Item -LiteralPath $runtime).Length)"

if($introLoop.Count -eq 0){
    $o+='post_intro_loop_scope_verdict=PASS_NO_INTRO_REWIND'
}else{
    $o+='post_intro_loop_scope_verdict=FAIL_INTRO_REWIND_OBSERVED'
}
if($mainAttach.Count -gt 0){
    $o+='post_intro_progress_verdict=MAIN_MENU_REACHED'
}else{
    $o+='post_intro_progress_verdict=MAIN_MENU_NOT_REACHED'
}
if($accessViolation.Count -eq 0){
    $o+='crash_verdict=NO_ACCESS_VIOLATION_OBSERVED'
}else{
    $o+='crash_verdict=ACCESS_VIOLATION_OBSERVED'
}

$o+='--- V74.0.88/V74.0.88.3 ---'
$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.88(\.3)?\]'}|Select-Object -First 1000)
$o+='--- post-intro/main-menu ---'
$o+=@($lines|Where-Object{$_ -match 'logo_intro_loop|main_menu(_ngp)?\.bk2|TITLE_TIMELINE|STALE_BINK|UI_BINK'}|Select-Object -First 1200)
$o+='--- crash ---'
$o+=@($accessViolation|Select-Object -First 300)

$o|Set-Content -LiteralPath $report -Encoding UTF8
$o|ForEach-Object{Write-Host $_}

$stage=Join-Path $env:TEMP ('SharpEmuV740883_'+$stamp)
New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log')
Copy-Item $report (Join-Path $stage 'result.log')
Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_88_3_POST_INTRO_LOOP_SCOPE_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force
Remove-Item $stage -Recurse -Force

Write-Host "RuntimeLog=$runtime"
Write-Host "ResultLog=$report"
Write-Host "RESULT ZIP=$zip"
