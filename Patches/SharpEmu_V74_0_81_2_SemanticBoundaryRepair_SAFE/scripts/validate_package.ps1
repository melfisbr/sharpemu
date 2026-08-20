param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$root=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){throw '[V74.0.81.2] manifest.sha256 ausente.'}
$lines=[System.IO.File]::ReadAllLines($manifest);$count=0
foreach($line in $lines){
 if([string]::IsNullOrWhiteSpace($line)){continue}
 $parts=$line -split '\s+\*',2
 if($parts.Count -ne 2){throw "[V74.0.81.2] linha de manifest invalida: $line"}
 $expected=$parts[0].Trim().ToLowerInvariant();$rel=$parts[1].Trim();$path=Join-Path $root $rel
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[V74.0.81.2] arquivo ausente: $rel"}
 $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
 if($actual -ne $expected){throw "[V74.0.81.2] hash divergente: $rel"};$count++
}
$parseErrors=New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File|ForEach-Object{
 $tokens=$null;$parseError=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parseError)
 if($parseError.Count -ne 0){foreach($e in $parseError){$parseErrors.Add("$($_.Name): $($e.Message)")}}
}
if($parseErrors.Count -ne 0){throw ("[V74.0.81.2] PowerShell parse failure:`n"+($parseErrors -join "`n"))}
Write-Host "[V74.0.81.2] PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed)." -ForegroundColor Green
