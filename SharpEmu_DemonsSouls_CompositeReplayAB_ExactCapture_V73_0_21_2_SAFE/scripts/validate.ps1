Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$manifest=[IO.Path]::Combine($pkg,'SHA256SUMS.txt')
if(-not [IO.File]::Exists($manifest)){throw 'SHA256SUMS.txt missing.'}

$scriptFiles=@(
    Get-ChildItem -LiteralPath ([IO.Path]::Combine($pkg,'scripts')) `
        -Filter '*.ps1' -File
)
foreach($f in $scriptFiles){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -gt 0){
        $detail=@($errors | ForEach-Object {
            "line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"
        }) -join ' | '
        throw "PowerShell parse failed: $($f.Name): $detail"
    }
}

foreach($line in [IO.File]::ReadAllLines($manifest)){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "Invalid manifest line: $line"
    }
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('/','\')
    $file=[IO.Path]::Combine($pkg,$relative)
    if(-not [IO.File]::Exists($file)){throw "Manifest file missing: $relative"}
    $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if($actual -ne $expected){
        throw "Hash mismatch: $relative expected=$expected actual=$actual"
    }
}

Write-Host "[V73.0.21.2] PACKAGE VALIDATION PASSED ($($scriptFiles.Count) PowerShell scripts parsed; manifest verified)." -ForegroundColor Green
Write-Host '[V73.0.21.2] This revision performs NO source patch.' -ForegroundColor Cyan
