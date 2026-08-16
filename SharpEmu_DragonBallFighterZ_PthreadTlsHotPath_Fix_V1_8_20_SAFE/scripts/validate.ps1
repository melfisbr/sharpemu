$ErrorActionPreference="Stop"
$packageRoot=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifest=Join-Path $packageRoot "SHA256SUMS.txt"
$lines=@(Get-Content -LiteralPath $manifest|Where-Object {$_.Trim() -ne ""})
foreach($line in $lines){
    if($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$'){throw "Bad manifest line: $line"}
    $p=Join-Path $packageRoot $matches[2]
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing package file: $($matches[2])"}
    $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()
    if($h -ne $matches[1].ToLowerInvariant()){throw "Hash mismatch: $($matches[2])"}
}
Get-ChildItem -LiteralPath $packageRoot -Recurse -Filter *.ps1|ForEach-Object{
    [void][scriptblock]::Create((Get-Content -LiteralPath $_.FullName -Raw))
}
. (Join-Path $PSScriptRoot "common.ps1")
$fixture='public static int PosixPthreadGetspecific(CpuContext ctx) { ctx[CpuRegister.Rax] = 0; return 0; }'
$m=Find-MethodBlock -Text $fixture -Signature 'public static int PosixPthreadGetspecific(CpuContext ctx)'
if($null -eq $m){throw "Method-block scanner regression failed."}
$apply=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw
foreach($x in @(
 'SHARPEMU_DBFZ_PTHREAD_TLS_HOTPATH_V1_8_20',
 '_pthreadTlsFastThreadHandle',
 '_pthreadTlsFastValues',
 'values.TryGetValue(key, out var storedValue)'
)){
    if(-not $apply.Contains($x)){throw "Patch payload regression missing: $x"}
}
Write-Host "[DBFZ-TLS-1820] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed)."
