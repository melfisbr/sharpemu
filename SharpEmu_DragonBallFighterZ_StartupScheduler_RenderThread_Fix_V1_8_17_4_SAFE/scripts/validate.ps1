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

$helperUsers=@(
    "offline_regression.ps1",
    "precheck.ps1",
    "apply_build.ps1",
    "post_audit.ps1"
)
foreach($name in $helperUsers){
    $scriptPath=Join-Path $PSScriptRoot $name
    $scriptText=Get-Content -LiteralPath $scriptPath -Raw
    if($scriptText.Contains("Get-NativeWorkerMaxDeclaration") -and
       -not $scriptText.Contains('common.ps1')){
        throw "Helper dependency regression: $name does not load common.ps1"
    }
}
Write-Host "[DBFZ-BOOT-18174] COMMON HELPER DEPENDENCY VALIDATION PASSED."

& (Join-Path $PSScriptRoot "offline_regression.ps1")
Write-Host "[DBFZ-BOOT-18174] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed)."
