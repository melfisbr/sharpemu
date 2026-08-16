param(
 [int]$Seconds=240,
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "post_audit.ps1")
$repo=Find-RepoRoot
$exe=Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){ throw "SharpEmu.exe missing: $exe" }
if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){ throw "DBFZ eboot missing: $Game" }

$outDir=Join-Path $repo ("DBFZ_NATIVE_WORKER_V1_8_18_RESULT_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdout=Join-Path $outDir "dragonball_stdout.log"
$stderr=Join-Path $outDir "dragonball_stderr.log"

Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
$sw=[Diagnostics.Stopwatch]::StartNew()
$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$splashMs=-1L
$entryMs=-1L
$deadline=(Get-Date).AddSeconds($Seconds)
while(-not $p.HasExited -and (Get-Date) -lt $deadline){
    Start-Sleep -Milliseconds 250
    $p.Refresh()
    if(Test-Path -LiteralPath $stderr -PathType Leaf){
        $tail=@(Get-Content -LiteralPath $stderr -Tail 300 -ErrorAction SilentlyContinue)
        if($entryMs -lt 0 -and ($tail -match '\[RUNTIME\] Entry:')){ $entryMs=$sw.ElapsedMilliseconds }
        if($splashMs -lt 0 -and ($tail -match 'presented splash')){ $splashMs=$sw.ElapsedMilliseconds }
    }
}
$survived=-not $p.HasExited
if($survived){ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$sw.Stop()

$l=if(Test-Path -LiteralPath $stderr){ @(Get-Content -LiteralPath $stderr) }else{ @() }

$prewarm=@($l | Select-String -Pattern 'Native guest workers prewarmed')
$create=@($l | Select-String -Pattern '\[DEDICATED\] create')
$run=@($l | Select-String -Pattern '\[DEDICATED\] run')
$criticalNames=@('AgcSubmissionThread','RHIThread','RenderThread 0','RTHeartBeat 0')
$critical=@()
foreach($name in $criticalNames){
    $c=@($l | Select-String -SimpleMatch "name='$name'" | Where-Object {$_.Line -match '\[DEDICATED\] create'}).Count
    $r=@($l | Select-String -SimpleMatch "name='$name'" | Where-Object {$_.Line -match '\[DEDICATED\] run'}).Count
    $critical += "$name create=$c run=$r"
}
$createAfter14=@($create | Where-Object {
    if($_.Line -match 'create n=(\d+)'){ [int]$matches[1] -ge 15 } else { $false }
})
$runNames=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($m in $run){
    if($m.Line -match "name='([^']+)'"){ [void]$runNames.Add($matches[1]) }
}
$createdAfter14Names=[System.Collections.Generic.List[string]]::new()
foreach($m in $createAfter14){
    if($m.Line -match "name='([^']+)'"){ $createdAfter14Names.Add($matches[1]) }
}
$after14RunUnique=@($createdAfter14Names | Where-Object { $runNames.Contains($_) } | Sort-Object -Unique)

$setupFull=@($l|Select-String -Pattern '\[LOADER\]\[INFO\] Setting up [0-9]+ import stubs')
$cacheHit=@($l|Select-String -SimpleMatch 'exec_setup_cache.v1817 hit')
$timeout=@($l|Select-String -Pattern 'timed out waiting for RenderThread|RenderingThread\.cpp.*1092')
$fatal=@($l|Select-String -Pattern 'LowLevelFatalError|Fatal error|Abort called|DeviceLost|Native exception')
$unresolved=@($l|Select-String -Pattern 'unresolved:')
$workerRefuse=@($l|Select-String -Pattern 'native worker|worker.*refus|worker.*unavailable|rent.*worker|executor.*unavailable')
$event=@($l|Select-String -SimpleMatch '[V17][EVENT_FASTPATH]')

$maxImport=0L
$maxLine='<none>'
foreach($line in $l){
    if($line -match 'Import#([0-9]+)'){
        $v=[long]$matches[1]
        if($v -gt $maxImport){ $maxImport=$v; $maxLine=$line }
    }
}
$prewarmLine=if($prewarm.Count -gt 0){ $prewarm[-1].Line }else{ '<none>' }

$summary=@(
 "Dragon Ball FighterZ NativeWorker Starvation Fix V1.8.18",
 "DiagnosticSeconds=$Seconds",
 "RuntimeSurvivedWindow=$survived",
 "TotalProcessMs=$($sw.ElapsedMilliseconds)",
 "RuntimeEntryObservedMs=$entryMs",
 "SplashObservedMs=$splashMs",
 "NativeWorkerPrewarm=$prewarmLine",
 "DedicatedCreateCount=$($create.Count)",
 "DedicatedRunCount=$($run.Count)",
 "CreateN15PlusCount=$($createAfter14.Count)",
 "CreatedN15PlusThatEverRan=$($after14RunUnique.Count)",
 "CreatedN15PlusRunNames=$([string]::Join('; ', $after14RunUnique))",
 "CriticalThreads=$([string]::Join(' | ', $critical))",
 "ImportSetupFullCount=$($setupFull.Count)",
 "ExecSetupCacheHitCount=$($cacheHit.Count)",
 "RenderThreadTimeoutCount=$($timeout.Count)",
 "FatalOrAbortCount=$($fatal.Count)",
 "UnresolvedImportCount=$($unresolved.Count)",
 "WorkerRefuseOrUnavailableEvidence=$($workerRefuse.Count)",
 "EventFastpathCount=$($event.Count)",
 "MaxObservedImportNumber=$maxImport",
 "MaxObservedImportLine=$maxLine"
)
$summary | Set-Content -LiteralPath (Join-Path $outDir "SUMMARY.txt") -Encoding utf8
$create.Line | Set-Content -LiteralPath (Join-Path $outDir "DEDICATED_CREATE.log") -Encoding utf8
$run.Line | Set-Content -LiteralPath (Join-Path $outDir "DEDICATED_RUN.log") -Encoding utf8
$workerRefuse.Line | Set-Content -LiteralPath (Join-Path $outDir "WORKER_EVIDENCE.log") -Encoding utf8
$unresolved.Line | Set-Content -LiteralPath (Join-Path $outDir "UNRESOLVED.log") -Encoding utf8

$zip="$outDir.zip"
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zip -Force
Write-Host ($summary -join "`n")
Write-Host "[DBFZ-WORKER-1818] RESULT ZIP: $zip"
