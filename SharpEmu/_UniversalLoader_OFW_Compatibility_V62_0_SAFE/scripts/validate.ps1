param([string]$PackageRoot)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($PackageRoot)){$PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path};$PackageRoot=$PackageRoot.Trim('"')
$m=Join-Path $PackageRoot 'SHA256SUMS.txt';if(!(Test-Path -LiteralPath $m)){throw 'SHA256SUMS.txt missing'};$e=@()
foreach($l in Get-Content $m){if(!$l){continue};$x=$l -split '\s+\*?',2;$p=Join-Path $PackageRoot $x[1].Replace('/','\');if(!(Test-Path $p)){$e+="missing $($x[1])"}elseif((Get-FileHash $p -Algorithm SHA256).Hash.ToUpperInvariant()-ne$x[0].ToUpperInvariant()){$e+="hash $($x[1])"}}
foreach($ps in Get-ChildItem $PackageRoot -Recurse -Filter *.ps1){$t=$null;$q=$null;[void][Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$t,[ref]$q);foreach($z in $q){$e+="$($ps.Name): $($z.Message)"}}
if($e.Count){throw($e -join '; ')};Write-Host '[V62.0] PACKAGE VALIDATION PASSED (hashes + PowerShell parser).'
