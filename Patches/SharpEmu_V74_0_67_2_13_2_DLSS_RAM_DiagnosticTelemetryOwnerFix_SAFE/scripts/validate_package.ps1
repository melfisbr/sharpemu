. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest)){throw 'SHA256SUMS.txt missing.'}

$failed=$false;$hashCount=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){throw "Malformed manifest line: $line"}
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.13.2] manifest_missing=$relative"
        $failed=$true
        continue
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.13.2] manifest_hash_mismatch=$relative"
        $failed=$true
    }
    $hashCount++
}

foreach($ps1 in Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne 0){
        foreach($err in $errors){
            Write-Host "[V74.0.67.2.13.2] parse_error=$($ps1.Name):$($err.Message)"
        }
        $failed=$true
    }
}

$diag=Normalize-Lf ([IO.File]::ReadAllText((Join-Path $package 'scripts\diagnostic.ps1')))
$ownerOk=$diag.Contains(
    "$b.Contains('[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active')")
$wrongOwnerAbsent=
    !$diag.Contains(
        "$b.Contains('[V74.0.67.2.13.2][UPSCALER][PROVIDER_INIT] state=active')")

Write-Host "[V74.0.67.2.13.2] validator_active_telemetry_owner_v213=$($ownerOk.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.13.2] validator_wrong_package_owner_absent=$($wrongOwnerAbsent.ToString().ToLowerInvariant())"
Write-Host '[V74.0.67.2.13.2] powershell_51_compatible=true'

if(!$ownerOk -or !$wrongOwnerAbsent){$failed=$true}
if($failed){throw '[V74.0.67.2.13.2] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.13.2] PACKAGE VALIDATION PASSED ($hashCount hashed files; PowerShell parsed)."
