. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw
$d=Get-WorkerCap -Text $wt

if($d.Value -eq 16 -and $mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));')){
    Write-Host "[DBFZ-OWN-1819] Worker state already normalized; build only."
} else {
    $backup=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_WorkerOwnership_V1_8_19_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    Copy-Item -LiteralPath $main -Destination (Join-Path $backup "DirectExecutionBackend.cs") -Force
    Copy-Item -LiteralPath $worker -Destination (Join-Path $backup "DirectExecutionBackend.NativeWorker.cs") -Force
    try {
        $oldPre='PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 12));'
        $newPre='PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));'
        if(-not $mt.Contains($oldPre)){ throw "12-worker prewarm rollback anchor missing." }
        $mt=$mt.Replace($oldPre,$newPre)
        Set-Content -LiteralPath $main -Value $mt -Encoding utf8

        $d=Get-WorkerCap -Text $wt
        if($null -eq $d -or $d.Value -ne 32){ throw "Expected worker cap 32 before rollback." }
        $replacement=[regex]::Replace($d.Text,'=\s*32\s*;','= 16;',1)
        $wt=$wt.Remove($d.Start,$d.Length).Insert($d.Start,$replacement)
        Set-Content -LiteralPath $worker -Value $wt -Encoding utf8
        Write-Host "[DBFZ-OWN-1819] Reverted ineffective worker experiment: cap 32 -> 16, prewarm 12 -> 8."
    } catch {
        Copy-Item -LiteralPath (Join-Path $backup "DirectExecutionBackend.cs") -Destination $main -Force
        Copy-Item -LiteralPath (Join-Path $backup "DirectExecutionBackend.NativeWorker.cs") -Destination $worker -Force
        throw
    }
}

Push-Location $repo
try {
    dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
    if($LASTEXITCODE -ne 0){ throw "dotnet build failed with exit code $LASTEXITCODE" }
} catch {
    if($backup){
        Copy-Item -LiteralPath (Join-Path $backup "DirectExecutionBackend.cs") -Destination $main -Force
        Copy-Item -LiteralPath (Join-Path $backup "DirectExecutionBackend.NativeWorker.cs") -Destination $worker -Force
        Write-Host "[DBFZ-OWN-1819] Rollback restored after build failure."
    }
    throw
} finally { Pop-Location }
Write-Host "[DBFZ-OWN-1819] BUILD PASSED."
if($backup){ Write-Host "[DBFZ-OWN-1819] Backup: $backup" }
