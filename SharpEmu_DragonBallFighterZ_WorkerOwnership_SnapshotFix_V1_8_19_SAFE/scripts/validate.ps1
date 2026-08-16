$ErrorActionPreference="Stop"
$packageRoot=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifest=Join-Path $packageRoot "SHA256SUMS.txt"
$lines=@(Get-Content -LiteralPath $manifest | Where-Object {$_.Trim() -ne ""})
foreach($line in $lines){
    if($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$'){ throw "Bad manifest line: $line" }
    $p=Join-Path $packageRoot $matches[2]
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){ throw "Missing package file: $($matches[2])" }
    $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()
    if($h -ne $matches[1].ToLowerInvariant()){ throw "Hash mismatch: $($matches[2])" }
}
Get-ChildItem -LiteralPath $packageRoot -Recurse -Filter *.ps1 | ForEach-Object {
    [void][scriptblock]::Create((Get-Content -LiteralPath $_.FullName -Raw))
}
. (Join-Path $PSScriptRoot "common.ps1")
$d=Get-WorkerCap -Text 'private static readonly int NativeWorkerMaxConcurrent = 32;'
if($null -eq $d -or $d.Value -ne 32){ throw "Worker-cap parser regression failed." }
$diag=Get-Content -LiteralPath (Join-Path $PSScriptRoot "diagnostic.ps1") -Raw
foreach($x in @('SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS','guest_thread.snapshot','CriticalSnapshotLast','N15PlusSnapshotStateCounts')){
    if(-not $diag.Contains($x)){ throw "Diagnostic regression missing: $x" }
}
Write-Host "[DBFZ-OWN-1819] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed)."
