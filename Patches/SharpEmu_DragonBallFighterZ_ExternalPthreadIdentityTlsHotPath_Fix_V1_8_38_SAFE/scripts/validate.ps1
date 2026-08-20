param([switch]$NoTranscript)
. (Join-Path $PSScriptRoot "common.ps1")
$t=Start-V1838Transcript "DBFZ_V1_8_38_RUN1_VALIDATE.log" -NoTranscript:$NoTranscript
try {
    $packageRoot=Split-Path -Parent $PSScriptRoot
    $manifest=Join-Path $packageRoot "SHA256SUMS.txt"
    if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "SHA256SUMS.txt missing."}
    $entries=@(Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach($entry in $entries){
        if($entry -notmatch '^([0-9a-fA-F]{64}) \*(.+)$'){throw "Invalid manifest line: $entry"}
        $expected=$matches[1].ToLowerInvariant()
        $rel=$matches[2].Replace('/','\')
        $path=Join-Path $packageRoot $rel
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Manifest file missing: $rel"}
        $actual=Get-Sha256Lower $path
        if($actual -ne $expected){throw "Hash mismatch: $rel"}
    }
    $ps=@(Get-ChildItem -LiteralPath $packageRoot -Recurse -Filter *.ps1 -File)
    foreach($f in $ps){
        $text=[IO.File]::ReadAllText($f.FullName)
        [void][scriptblock]::Create($text)
    }
    $cmd=@(Get-ChildItem -LiteralPath $packageRoot -Filter RUN_*.cmd -File)
    foreach($f in $cmd){
        $content=[IO.File]::ReadAllText($f.FullName)
        if($content -notmatch 'scripts\\[^"]+\.ps1'){throw "CMD target missing in $($f.Name)"}
        $m=[regex]::Match($content,'scripts\\([^"]+\.ps1)')
        $target=Join-Path $PSScriptRoot $m.Groups[1].Value
        if(-not(Test-Path -LiteralPath $target -PathType Leaf)){throw "CMD script target missing: $target"}
    }
    & (Join-Path $PSScriptRoot "offline_regression.ps1")
    Write-Host "[DBFZ-CPU-1838] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed; CMD targets verified)."
} finally { Stop-V1838Transcript $t }
