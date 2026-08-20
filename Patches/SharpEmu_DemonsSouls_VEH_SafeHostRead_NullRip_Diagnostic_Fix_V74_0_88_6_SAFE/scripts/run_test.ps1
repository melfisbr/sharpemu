. "$PSScriptRoot\common.ps1"
$p=Paths
$patches=Patches
$pkg=PackageRoot

try{
    Assert-V740886|Out-Null
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
$runtime=Join-Path $patches ('SharpEmu_V74_0_88_6_VEH_SAFE_HOST_READ_LIVE_RUNTIME_'+$stamp+'.log')
$report=Join-Path $patches ('SharpEmu_V74_0_88_6_VEH_SAFE_HOST_READ_RESULT_'+$stamp+'.log')
$zip=Join-Path $patches ('SharpEmu_V74_0_88_6_VEH_SAFE_HOST_READ_RESULT_'+$stamp+'.zip')

# Preserve the accumulated Demon's Souls runtime configuration.
$env:SHARPEMU_DS_UI_BINK_INTERNAL='1'
$env:SHARPEMU_DS_UI_BINK_STICKY_PLANES='1'
$env:SHARPEMU_DS_UI_BINK_LOOP='1'
$env:SHARPEMU_DS_DCC_EXACT_FORMAT='1'
Remove-Item Env:SHARPEMU_IME_TEXT -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_IME_HOST_PANEL -ErrorAction SilentlyContinue

try{[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)}catch{}

Write-Host ''
Write-Host "$script:Tag TESTE:" -ForegroundColor Cyan
Write-Host '1. Inicie normalmente. O objetivo imediato e ultrapassar a criacao das threads HighGraphics/Core.Res.* sem fatal managed AccessViolation.'
Write-Host '2. Se chegar aos videos/title loop, continue normalmente.'
Write-Host '3. Se chegar em NEW GAME/Character Creation, teste fundo Bink, modelo 3D e IME.'
Write-Host '4. Se houver novo crash, nao precisa capturar manualmente: o log e gravado ao vivo em Patches.'
Write-Host ''
Write-Host "$script:Tag LIVE_RUNTIME_LOG=$runtime" -ForegroundColor Yellow
Write-Host ''

$utf8=New-Object Text.UTF8Encoding($false)
$writer=New-Object IO.StreamWriter($runtime,$false,$utf8)
$writer.AutoFlush=$true
$exitCode=-1

# V74.0.88.6 NATIVE_STDERR_MERGE
$escapedExe=$p.Exe.Replace('"','""')
$escapedEboot=$eboot.Replace('"','""')
$cmdLine='""{0}" "{1}" 2>&1"' -f $escapedExe,$escapedEboot

try{
    & $env:ComSpec /D /S /C $cmdLine | ForEach-Object {
        $line=[string]$_
        $writer.WriteLine($line)
        if($line -match '\[V74\.0\.88\.6\]' -or
           $line -match 'VEH_AV first-chance|NATIVE EXCEPTION CAUGHT|Fatal error|ACCESS_VIOLATION|Bink2 NIHAV bridge attached: main_menu'){
            Write-Host $line
        }
    }
    $exitCode=$LASTEXITCODE
}
finally{
    $writer.Flush()
    $writer.Dispose()
}

$all=if(Test-Path -LiteralPath $runtime){[IO.File]::ReadAllText($runtime)}else{''}
$lines=$all -split "`r?`n"

$safeReject=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.6\]\[VEH_SAFE_READ_REJECT\]'})
$nullRip=@($lines|Where-Object{$_ -match 'VEH_AV first-chance at 0x0{16} type=8 target=0x0{16}|RIP: 0x0{16}'})
$managedAv=@($lines|Where-Object{$_ -match 'System\.AccessViolationException'})
$tryReadFatal=@($lines|Where-Object{$_ -match 'DirectExecutionBackend\.TryReadHostQword'})
$handlerFatal=@($lines|Where-Object{$_ -match 'DirectExecutionBackend\.VectoredHandler'})
$binkAttach=@($lines|Where-Object{$_ -match 'Bink2 (NIHAV|RAD) bridge attached'})
$mainAttach=@($lines|Where-Object{$_ -match 'Bink2 NIHAV bridge attached: main_menu(_ngp)?\.bk2'})
$imeOpen=@($lines|Where-Object{$_ -match '\[V74\.0\.88\]\[IME_IN_WINDOW\] open '})

$o=@()
$o+="$script:Tag RUNTIME RESULT"
$o+="ExitCode=$exitCode"
$o+="veh_safe_read_reject_count=$($safeReject.Count)"
$o+="veh_null_rip_count=$($nullRip.Count)"
$o+="fatal_managed_access_violation_count=$($managedAv.Count)"
$o+="try_read_host_qword_fatal_stack_count=$($tryReadFatal.Count)"
$o+="vectored_handler_fatal_stack_count=$($handlerFatal.Count)"
$o+="bink_attach_count=$($binkAttach.Count)"
$o+="main_menu_attach_count=$($mainAttach.Count)"
$o+="ime_in_window_open_count=$($imeOpen.Count)"
$o+="runtime_log_bytes=$((Get-Item -LiteralPath $runtime).Length)"

if($managedAv.Count -eq 0 -and $tryReadFatal.Count -eq 0){
    $o+='veh_host_probe_verdict=PASS_NO_MANAGED_AV_IN_SAFE_READ'
}else{
    $o+='veh_host_probe_verdict=FAIL_MANAGED_AV_STILL_PRESENT'
}
if($nullRip.Count -gt 0){
    $o+='guest_null_rip_verdict=NULL_RIP_STILL_REPRODUCED'
}else{
    $o+='guest_null_rip_verdict=NULL_RIP_NOT_OBSERVED'
}
if($mainAttach.Count -gt 0){
    $o+='progress_verdict=MAIN_MENU_REACHED'
}elseif($binkAttach.Count -gt 0){
    $o+='progress_verdict=BINK_STAGE_REACHED'
}else{
    $o+='progress_verdict=PRE_BINK_STAGE'
}

$o+='--- safe read / VEH ---'
$o+=@($lines|Where-Object{$_ -match '\[V74\.0\.88\.6\]|VEH_AV first-chance|NATIVE EXCEPTION CAUGHT|TryReadHostQword|VectoredHandler|System\.AccessViolationException'}|Select-Object -First 1800)
$o+='--- thread startup / imports ---'
$o+=@($lines|Where-Object{$_ -match 'DS-THREADSTART|Core\.Res\.|HighGraphics|last_import=|Last import registers'}|Select-Object -First 1800)
$o+='--- progress ---'
$o+=@($lines|Where-Object{$_ -match 'Bink2 .*bridge attached|TITLE_TIMELINE|main_menu|IME_IN_WINDOW'}|Select-Object -First 1200)

$o|Set-Content -LiteralPath $report -Encoding UTF8
$o|ForEach-Object{Write-Host $_}

$stage=Join-Path $env:TEMP ('SharpEmuV740886_'+$stamp)
New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log')
Copy-Item $report (Join-Path $stage 'result.log')
Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_88_6_VEH_SAFE_HOST_READ_BUILD_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($latest){Copy-Item $latest.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force
Remove-Item $stage -Recurse -Force

Write-Host "RuntimeLog=$runtime"
Write-Host "ResultLog=$report"
Write-Host "RESULT ZIP=$zip"
