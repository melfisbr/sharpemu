param([string]$PackageRoot)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($PackageRoot)){$PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path}
$manifest=Join-Path $PackageRoot 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest)){throw 'manifest missing'}
$errs=@()
foreach($l in Get-Content -LiteralPath $manifest){if(!$l){continue};$x=$l -split '\s+\*?',2;$p=Join-Path $PackageRoot $x[1].Replace('/','\');if(!(Test-Path -LiteralPath $p)){$errs+="missing $($x[1])"}elseif((Get-FileHash $p -Algorithm SHA256).Hash-ne$x[0]){$errs+="hash $($x[1])"}}
foreach($p in Get-ChildItem $PackageRoot -Recurse -Filter *.ps1){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($p.FullName,[ref]$t,[ref]$e);foreach($q in $e){$errs+="$($p.Name): $($q.Message)"}}
if($errs.Count){throw($errs -join '; ')}
Write-Host '[V61.24.1] PACKAGE VALIDATION PASSED.'
