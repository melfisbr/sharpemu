param(
 [int]$Seconds=240,
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "post_audit.ps1")
$repo=Find-RepoRoot
$exe=Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "SharpEmu.exe missing: $exe"}

$outDir=Join-Path $repo ("DBFZ_PTHREAD_TLS_V1_8_20_RESULT_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir|Out-Null
$stdout=Join-Path $outDir "dragonball_stdout.log"
$stderr=Join-Path $outDir "dragonball_stderr.log"

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$sw=[Diagnostics.Stopwatch]::StartNew()
$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$splashMs=-1L
$deadline=(Get-Date).AddSeconds($Seconds)
while(-not $p.HasExited -and (Get-Date) -lt $deadline){
    Start-Sleep -Milliseconds 250
    $p.Refresh()
    if($splashMs -lt 0 -and (Test-Path -LiteralPath $stderr)){
        $tail=@(Get-Content -LiteralPath $stderr -Tail 250 -ErrorAction SilentlyContinue)
        if($tail -match 'presented splash'){$splashMs=$sw.ElapsedMilliseconds}
    }
}
$survived=-not $p.HasExited
if($survived){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
$sw.Stop()

$l=if(Test-Path -LiteralPath $stderr){@(Get-Content -LiteralPath $stderr)}else{@()}
$progress=@($l|Select-String -SimpleMatch 'dbfz.import_progress.v1892')
$timeout=@($l|Select-String -Pattern 'timed out waiting for RenderThread|RenderingThread\.cpp.*1092')
$fatal=@($l|Select-String -Pattern 'LowLevelFatalError|Fatal error|Abort called|DeviceLost|Native exception')
$unresolved=@($l|Select-String -Pattern 'unresolved:')
$cache=@($l|Select-String -SimpleMatch 'exec_setup_cache.v1817 hit')
$prewarm=@($l|Select-String -Pattern 'Native guest workers prewarmed')
$lastProgress=if($progress.Count -gt 0){$progress[-1].Line}else{'<none>'}
$prewarmLine=if($prewarm.Count -gt 0){$prewarm[-1].Line}else{'<none>'}

$maxImport=0L
foreach($line in $l){
    if($line -match 'Import#([0-9]+)'){
        $v=[long]$matches[1]
        if($v -gt $maxImport){$maxImport=$v}
    }
}

$summary=@(
 "Dragon Ball FighterZ Pthread TLS HotPath V1.8.20",
 "DiagnosticSeconds=$Seconds",
 "RuntimeSurvivedWindow=$survived",
 "TotalProcessMs=$($sw.ElapsedMilliseconds)",
 "SplashObservedMs=$splashMs",
 "BaselineSplashMs=199360",
 "SplashDeltaMs=$([long]$splashMs-199360)",
 "NativeWorkerPrewarm=$prewarmLine",
 "ExecSetupCacheHitCount=$($cache.Count)",
 "LastSparseProgress=$lastProgress",
 "MaxObservedImportNumber=$maxImport",
 "RenderThreadTimeoutCount=$($timeout.Count)",
 "FatalOrAbortCount=$($fatal.Count)",
 "UnresolvedImportCount=$($unresolved.Count)"
)
$summary|Set-Content -LiteralPath (Join-Path $outDir "SUMMARY.txt") -Encoding utf8
$progress.Line|Set-Content -LiteralPath (Join-Path $outDir "IMPORT_PROGRESS.log") -Encoding utf8
$unresolved.Line|Set-Content -LiteralPath (Join-Path $outDir "UNRESOLVED.log") -Encoding utf8
$zip="$outDir.zip"
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zip -Force
Write-Host ($summary -join "`n")
Write-Host "[DBFZ-TLS-1820] RESULT ZIP: $zip"
