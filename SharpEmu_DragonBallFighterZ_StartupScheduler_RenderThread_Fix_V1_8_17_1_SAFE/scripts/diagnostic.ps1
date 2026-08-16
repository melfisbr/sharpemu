param(
 [int]$Seconds=240,
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "post_audit.ps1")
$repo=Find-RepoRoot
$exe=Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "SharpEmu.exe missing: $exe"}
if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){throw "DBFZ eboot missing: $Game"}

$out=Join-Path $repo ("DBFZ_STARTUP_SCHEDULER_V1_8_17_RESULT_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out "dragonball_stdout.log"
$stderr=Join-Path $out "dragonball_stderr.log"

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$sw=[Diagnostics.Stopwatch]::StartNew()
$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

$splashMs=-1L
$runtimeEntryMs=-1L
$deadline=(Get-Date).AddSeconds($Seconds)
while(-not $p.HasExited -and (Get-Date) -lt $deadline){
    Start-Sleep -Milliseconds 250
    $p.Refresh()
    if(Test-Path -LiteralPath $stderr -PathType Leaf){
        $tail=Get-Content -LiteralPath $stderr -Tail 250 -ErrorAction SilentlyContinue
        if($runtimeEntryMs -lt 0 -and ($tail -match '\[RUNTIME\] Entry:')){$runtimeEntryMs=$sw.ElapsedMilliseconds}
        if($splashMs -lt 0 -and ($tail -match 'presented splash')){$splashMs=$sw.ElapsedMilliseconds}
    }
}
$survived=-not $p.HasExited
if($survived){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
$sw.Stop()

$l=if(Test-Path -LiteralPath $stderr){@(Get-Content -LiteralPath $stderr)}else{@()}
$setupFull=@($l|Select-String -Pattern '\[LOADER\]\[INFO\] Setting up [0-9]+ import stubs')
$cacheHit=@($l|Select-String -SimpleMatch 'exec_setup_cache.v1817 hit')
$cachePrime=@($l|Select-String -SimpleMatch 'exec_setup_cache.v1817 primed')
$prewarm=@($l|Select-String -Pattern 'Native guest workers prewarmed')
$renderCreate=@($l|Select-String -Pattern "\[DEDICATED\] create .*name='RenderThread 0'")
$renderRun=@($l|Select-String -Pattern "\[DEDICATED\] run .*name='RenderThread 0'")
$rhiRun=@($l|Select-String -Pattern "\[DEDICATED\] run .*name='RHIThread'")
$agcRun=@($l|Select-String -Pattern "\[DEDICATED\] run .*name='AgcSubmissionThread'")
$heartbeatRun=@($l|Select-String -Pattern "\[DEDICATED\] run .*name='RTHeartBeat 0'")
$timeout=@($l|Select-String -Pattern 'timed out waiting for RenderThread|RenderingThread\.cpp.*1092')
$fatal=@($l|Select-String -Pattern 'LowLevelFatalError|Fatal error|Abort called|DeviceLost|Native exception')
$events=@($l|Select-String -SimpleMatch '[V17][EVENT_FASTPATH]')
$mkdirExists=@($l|Select-String -Pattern 'ORBIS_GEN2_ERROR_ALREADY_EXISTS \(1-LFLmRFxxM\)')
$unresolved=@($l|Select-String -Pattern 'unresolved:')
$warm=@($l|Select-String -Pattern '\[HLE\] Warmed ')
$preload=@($l|Select-String -Pattern 'Module preload summary:')
$rebind=@($l|Select-String -Pattern 'Imported data rebind: .*unresolved=0')

$maxImport=0L
$maxLine='<none>'
foreach($line in $l){
    if($line -match 'Import#([0-9]+)'){
        $v=[long]$matches[1]
        if($v -gt $maxImport){$maxImport=$v;$maxLine=$line}
    }
}

$summary=@(
 "Dragon Ball FighterZ Startup/Scheduler/RenderThread V1.8.17.1",
 "DiagnosticSeconds=$Seconds",
 "RuntimeSurvivedWindow=$survived",
 "TotalProcessMs=$($sw.ElapsedMilliseconds)",
 "RuntimeEntryObservedMs=$runtimeEntryMs",
 "SplashObservedMs=$splashMs",
 "ImportSetupFullCount=$($setupFull.Count)",
 "ExecSetupCachePrimeCount=$($cachePrime.Count)",
 "ExecSetupCacheHitCount=$($cacheHit.Count)",
 "NativeWorkerPrewarm=$((if($prewarm.Count){$prewarm[-1].Line}else{'<none>'}))",
 "RenderThreadCreateCount=$($renderCreate.Count)",
 "RenderThreadRunCount=$($renderRun.Count)",
 "RHIThreadRunCount=$($rhiRun.Count)",
 "AgcSubmissionRunCount=$($agcRun.Count)",
 "RTHeartBeatRunCount=$($heartbeatRun.Count)",
 "RenderThreadTimeoutCount=$($timeout.Count)",
 "FatalOrAbortCount=$($fatal.Count)",
 "EventFastpathCount=$($events.Count)",
 "MkdirAlreadyExistsCount=$($mkdirExists.Count)",
 "UnresolvedImportCount=$($unresolved.Count)",
 "WarmupLine=$((if($warm.Count){$warm[0].Line}else{'<none>'}))",
 "ModulePreloadLine=$((if($preload.Count){$preload[-1].Line}else{'<none>'}))",
 "ImportedDataRebindClean=$($rebind.Count -gt 0)",
 "MaxObservedImportNumber=$maxImport",
 "MaxObservedImportLine=$maxLine"
)
$summary|Set-Content -LiteralPath (Join-Path $out "SUMMARY.txt") -Encoding utf8
$setupFull.Line|Set-Content -LiteralPath (Join-Path $out "IMPORT_SETUP_FULL.log") -Encoding utf8
$cacheHit.Line|Set-Content -LiteralPath (Join-Path $out "IMPORT_SETUP_CACHE_HITS.log") -Encoding utf8
@($renderCreate.Line+$renderRun.Line+$rhiRun.Line+$agcRun.Line+$heartbeatRun.Line)|Set-Content -LiteralPath (Join-Path $out "CRITICAL_THREADS.log") -Encoding utf8
$timeout.Line|Set-Content -LiteralPath (Join-Path $out "RENDER_TIMEOUT.log") -Encoding utf8
$unresolved.Line|Set-Content -LiteralPath (Join-Path $out "UNRESOLVED.log") -Encoding utf8

$zip="$out.zip"
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force
Write-Host ($summary -join "`n")
Write-Host "[DBFZ-BOOT-18171] RESULT ZIP: $zip"
