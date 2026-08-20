. "$PSScriptRoot\common.ps1"
$p=Paths
$patches=Patches
$pkg=PackageRoot

try{
    Assert-V740885 $p.Repo
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
$runtime=Join-Path $patches ('SharpEmu_V74_0_88_5_STABLE_HOST_PLANE_LIVE_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_88_5_STABLE_HOST_PLANE_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_88_5_STABLE_HOST_PLANE_RESULT_'+$stamp+'.zip')

$env:SHARPEMU_DS_UI_BINK_INTERNAL='1'
$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1'
$env:SHARPEMU_DS_UI_BINK_LOOP='1'
$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1'
Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_IME_HOST_PANEL -ErrorAction SilentlyContinue

try{
    [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
}catch{}

Write-Host ''
Write-Host "$script:Tag TESTE:" -ForegroundColor Cyan
Write-Host '1. Percorra o boot normalmente ate o logo_intro_loop / PRESS ANY BUTTON.'
Write-Host '2. Confirme se o emulador ultrapassa o ponto que antes dava 0xC0000005.'
Write-Host '3. Se chegar em NEW GAME, permaneça por pelo menos 30 segundos.'
Write-Host '4. Entre em Character Creation e confirme fundo Bink, modelo 3D e IME dentro da janela.'
Write-Host '5. Se houver novo crash/travamento, feche o SharpEmu. O log ja esta sendo gravado em Patches.'
Write-Host ''
Write-Host "$script:Tag LIVE_RUNTIME_LOG=$runtime" -ForegroundColor Yellow
Write-Host ''

$utf8=New-Object Text.UTF8Encoding($false)
$writer=New-Object IO.StreamWriter($runtime,$false,$utf8)
$writer.AutoFlush=$true
$exitCode=-1

# V74.0.88.5 NATIVE_STDERR_MERGE
$escapedExe=$p.Exe.Replace('"','""')
$escapedEboot=$eboot.Replace('"','""')
$cmdLine='""{0}" "{1}" 2>&1"' -f $escapedExe,$escapedEboot

try{
    & $env:ComSpec /D /S /C $cmdLine | ForEach-Object {
        $line=[string]$_
        $writer.WriteLine($line)

        if($line -match '\[V74\.0\.88\.5\]' -or
           $line -match '\[V74\.0\.88\.3\]\[MAIN_MENU_LOOP_RESTART\]' -or
           $line -match 'ACCESS_VIOLATION|Fatal error|DEVICE_LOST|VK_ERROR_DEVICE_LOST'){
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

$hostUploads=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.5\]\[HOST_MOVIE_UPLOAD\]'})
$hostUploadInvalid=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.5\]\[HOST_MOVIE_UPLOAD_INVALID\]'})
$mainAttach=@($lines|Where-Object{$_ -match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2'})
$mainLoop=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.3\]\[MAIN_MENU_LOOP_RESTART\].*result=rewound'})
$imeOpen=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_IN_WINDOW\] open '})
$imeCommit=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_DIALOG\] text_commit '})
$accessViolation=@($lines|Where-Object{$_ -match 'ACCESS_VIOLATION|Fatal error\.'})
$copyCrash=@($lines|Where-Object{$_ -match 'Vk\.CmdCopyBufferToImage|RecordTextureUploads'})
$deviceLost=@($lines|Where-Object{$_ -match 'DEVICE_LOST|VK_ERROR_DEVICE_LOST'})

$o=@()
$o+="$script:Tag RUNTIME RESULT"
$o+="ExitCode=$exitCode"
$o+="host_movie_upload_count=$($hostUploads.Count)"
$o+="host_movie_upload_invalid_count=$($hostUploadInvalid.Count)"
$o+="copy_buffer_crash_signature_count=$($copyCrash.Count)"
$o+="main_menu_attach_count=$($mainAttach.Count)"
$o+="main_menu_loop_restart_count=$($mainLoop.Count)"
$o+="ime_in_window_open_count=$($imeOpen.Count)"
$o+="ime_text_commit_count=$($imeCommit.Count)"
$o+="access_violation_count=$($accessViolation.Count)"
$o+="device_lost_count=$($deviceLost.Count)"
$o+="runtime_log_bytes=$((Get-Item -LiteralPath $runtime).Length)"

if($accessViolation.Count -eq 0 -and $copyCrash.Count -eq 0){
    $o+='title_loop_upload_verdict=PASS_NO_CMD_COPY_CRASH'
}else{
    $o+='title_loop_upload_verdict=FAIL_CMD_COPY_CRASH_OR_AV'
}

if($mainAttach.Count -gt 0){
    $o+='post_intro_progress_verdict=MAIN_MENU_REACHED'
}else{
    $o+='post_intro_progress_verdict=MAIN_MENU_NOT_REACHED'
}

if($imeOpen.Count -gt 0){
    $o+='ime_verdict=IN_WINDOW_IME_REACHED'
}else{
    $o+='ime_verdict=IME_NOT_REACHED'
}

$o+='--- V74.0.88.5 host uploads ---'
$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.5\]\[HOST_MOVIE_UPLOAD'}|Select-Object -First 1200)
$o+='--- Bink title/menu ---'
$o+=@($lines|Where-Object{$_ -match 'logo_intro_loop\.bk2|main_menu(_ngp)?\.bk2|Bink2 YUV textures bound|UI_BINK_STICKY_PLANE'}|Select-Object -First 1800)
$o+='--- fatal ---'
$o+=@($lines|Where-Object{$_ -match 'ACCESS_VIOLATION|Fatal error\.|CmdCopyBufferToImage|RecordTextureUploads|DEVICE_LOST|VK_ERROR_DEVICE_LOST'}|Select-Object -First 600)

$o|Set-Content -LiteralPath $report -Encoding UTF8
$o|ForEach-Object{Write-Host $_}

$stage=Join-Path $env:TEMP ('SharpEmuV740885_'+$stamp)
New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log')
Copy-Item $report (Join-Path $stage 'result.log')
Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage

$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_88_5_STABLE_HOST_PLANE_BUILD_*.log' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if($latest){
    Copy-Item $latest.FullName (Join-Path $stage 'build.log')
}

Compress-Archive (Join-Path $stage '*') $zip -Force
Remove-Item $stage -Recurse -Force

Write-Host "RuntimeLog=$runtime"
Write-Host "ResultLog=$report"
Write-Host "RESULT ZIP=$zip"
