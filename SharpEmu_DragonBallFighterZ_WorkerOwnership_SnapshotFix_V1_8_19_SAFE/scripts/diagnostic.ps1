param(
 [int]$Seconds=240,
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "post_audit.ps1")
$repo=Find-RepoRoot
$exe=Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){ throw "SharpEmu.exe missing: $exe" }

$outDir=Join-Path $repo ("DBFZ_WORKER_OWNERSHIP_V1_8_19_RESULT_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdout=Join-Path $outDir "dragonball_stdout.log"
$stderr=Join-Path $outDir "dragonball_stderr.log"

Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
$oldSnapshots=$env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS
$env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS='1'
try {
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $splashMs=-1L
    $deadline=(Get-Date).AddSeconds($Seconds)
    while(-not $p.HasExited -and (Get-Date) -lt $deadline){
        Start-Sleep -Milliseconds 250
        $p.Refresh()
        if($splashMs -lt 0 -and (Test-Path -LiteralPath $stderr)){
            $tail=@(Get-Content -LiteralPath $stderr -Tail 250 -ErrorAction SilentlyContinue)
            if($tail -match 'presented splash'){ $splashMs=$sw.ElapsedMilliseconds }
        }
    }
    $survived=-not $p.HasExited
    if($survived){ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    $sw.Stop()
} finally {
    if($null -eq $oldSnapshots){ Remove-Item Env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS -ErrorAction SilentlyContinue }
    else{ $env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS=$oldSnapshots }
}

$l=if(Test-Path -LiteralPath $stderr){ @(Get-Content -LiteralPath $stderr) }else{ @() }
$snap=@($l | Select-String -SimpleMatch 'guest_thread.snapshot')
$create=@($l | Select-String -Pattern '\[DEDICATED\] create')
$run=@($l | Select-String -Pattern '\[DEDICATED\] run')

$criticalNames=@('HttpManagerThread','OnlineAsyncTaskThreadPS5 Defau','AgcSubmissionThread','RHIThread','RenderThread 0','RTHeartBeat 0')
$criticalLast=[System.Collections.Generic.List[string]]::new()
foreach($name in $criticalNames){
    $sm=@($snap | Where-Object {$_.Line -like "*name='$name'*"})
    if($sm.Count -gt 0){ $criticalLast.Add($sm[-1].Line) }
    else{ $criticalLast.Add("$name snapshot=<none>") }
}

$createdN15Names=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($m in $create){
    if($m.Line -match "create n=(\d+).*name='([^']+)'"){
        if([int]$matches[1] -ge 15){ [void]$createdN15Names.Add($matches[2]) }
    }
}
$stateCounts=@{}
foreach($m in $snap){
    if($m.Line -match "name='([^']+)'.*state=([A-Za-z]+).*executor=([A-Za-z]+)"){
        $nm=$matches[1]
        if($createdN15Names.Contains($nm)){
            $key="$($matches[2])/executor=$($matches[3])"
            if(-not $stateCounts.ContainsKey($key)){ $stateCounts[$key]=0 }
            $stateCounts[$key]++
        }
    }
}
$stateSummary=(($stateCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {$_.Name+'='+$_.Value}) -join '; ')

$timeout=@($l|Select-String -Pattern 'timed out waiting for RenderThread|RenderingThread\.cpp.*1092')
$fatal=@($l|Select-String -Pattern 'LowLevelFatalError|Fatal error|Abort called|DeviceLost|Native exception')
$unresolved=@($l|Select-String -Pattern 'unresolved:')
$prewarm=@($l|Select-String -Pattern 'Native guest workers prewarmed')
$prewarmLine=if($prewarm.Count -gt 0){$prewarm[-1].Line}else{'<none>'}

$summary=@(
 "Dragon Ball FighterZ Worker Ownership Snapshot V1.8.19",
 "DiagnosticSeconds=$Seconds",
 "RuntimeSurvivedWindow=$survived",
 "TotalProcessMs=$($sw.ElapsedMilliseconds)",
 "SplashObservedMs=$splashMs",
 "NativeWorkerPrewarm=$prewarmLine",
 "DedicatedCreateCount=$($create.Count)",
 "DedicatedRunCount=$($run.Count)",
 "SnapshotCount=$($snap.Count)",
 "N15PlusSnapshotStateCounts=$stateSummary",
 "CriticalSnapshotLast=$([string]::Join(' || ', $criticalLast))",
 "RenderThreadTimeoutCount=$($timeout.Count)",
 "FatalOrAbortCount=$($fatal.Count)",
 "UnresolvedImportCount=$($unresolved.Count)"
)
$summary | Set-Content -LiteralPath (Join-Path $outDir "SUMMARY.txt") -Encoding utf8
$snap.Line | Set-Content -LiteralPath (Join-Path $outDir "GUEST_THREAD_SNAPSHOTS.log") -Encoding utf8
$criticalLast | Set-Content -LiteralPath (Join-Path $outDir "CRITICAL_LAST_SNAPSHOT.log") -Encoding utf8
$create.Line | Set-Content -LiteralPath (Join-Path $outDir "DEDICATED_CREATE.log") -Encoding utf8
$run.Line | Set-Content -LiteralPath (Join-Path $outDir "DEDICATED_RUN.log") -Encoding utf8
$unresolved.Line | Set-Content -LiteralPath (Join-Path $outDir "UNRESOLVED.log") -Encoding utf8

$zip="$outDir.zip"
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zip -Force
Write-Host ($summary -join "`n")
Write-Host "[DBFZ-OWN-1819] RESULT ZIP: $zip"
