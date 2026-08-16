Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$manifest=[IO.Path]::Combine($root,'SHA256SUMS.txt')
if(-not [IO.File]::Exists($manifest)){throw 'SHA256SUMS.txt missing.'}
$scripts=@(Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'scripts')) -File -Filter '*.ps1')
foreach($s in $scripts){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($s.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count -gt 0){
        $d=@($errors|ForEach-Object{"line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"}) -join ' | '
        throw "PowerShell parse failed: $($s.Name): $d"
    }
}
foreach($line in [IO.File]::ReadAllLines($manifest)){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "Bad manifest line: $line"}
    $p=[IO.Path]::Combine($root,$matches[2].Replace('/','\'))
    if(-not [IO.File]::Exists($p)){throw "Manifest file missing: $p"}
    if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $matches[1].ToUpperInvariant()){throw "Manifest hash mismatch: $p"}
}
Write-Host "[V74.0.26] PACKAGE VALIDATION PASSED ($($scripts.Count) PowerShell scripts parsed; manifest verified)." -ForegroundColor Green
