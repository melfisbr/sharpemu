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
$fixture='private static readonly int NativeWorkerMaxConcurrent = 16;'
$d=Get-NativeWorkerDeclaration -Text $fixture
if($null -eq $d -or $d.Value -ne 16){ throw "Worker declaration regression failed." }
Write-Host "[DBFZ-WORKER-1818] OFFLINE DECLARATION REGRESSION PASSED."
Write-Host "[DBFZ-WORKER-1818] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed)."
