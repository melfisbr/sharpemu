$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'common.ps1')
$manifest=Join-Path $PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'manifest.sha256 ausente'}
$lines=Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach($line in $lines){
    if($line -notmatch '^([0-9a-f]{64})  (.+)$'){throw "Manifest invalido: $line"}
    $expected=$Matches[1]; $rel=$Matches[2].Replace('/','\')
    $path=Join-Path $PackageRoot $rel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Arquivo do manifest ausente: $rel"}
    $actual=Get-Sha256 $path
    if($actual -ne $expected){throw "Hash mismatch: $rel expected=$expected actual=$actual"}
}
foreach($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter *.ps1 -File){
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -ne 0){throw "PowerShell parse failed: $($script.FullName): $($errors[0].Message)"}
}
# V76.0.18.4: PowerShell variable names are case-insensitive.  $host therefore
# aliases the read-only automatic variable $Host and must never be assigned.
foreach($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter *.ps1 -File){
    if($script.FullName -eq $PSCommandPath){continue}
    $text=[System.IO.File]::ReadAllText($script.FullName)
    if($text -match '(?im)^\s*\$host\s*='){
        throw "Read-only automatic variable assignment prohibited: $($script.FullName): `$Host"
    }
}
foreach($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1','.cmd','.md' }){
    if($script.FullName -eq (Join-Path $PSScriptRoot 'validate.ps1')){continue}
    $text=[System.IO.File]::ReadAllText($script.FullName)
    if($text -match '(?i)Invoke-WebRequest|Start-BitsTransfer|curl\.exe|wget\.exe|DownloadFile\('){throw "Downloader de rede proibido: $($script.FullName)"}
}
foreach($spec in $PatchSpecs){
    $old=Read-Text (Join-Path $PackageRoot "patchdata\$($spec.Name).old.txt")
    $new=Read-Text (Join-Path $PackageRoot "patchdata\$($spec.Name).new.txt")
    if([string]::IsNullOrWhiteSpace($old) -or [string]::IsNullOrWhiteSpace($new)){throw "Patchdata vazio: $($spec.Name)"}
    if($old -eq $new){throw "Patchdata old=new: $($spec.Name)"}
}
$helper=Read-Text (Join-Path $PackageRoot $HandoffPayload)
foreach($marker in @('CompleteGuestBinkHandoffV7618','ResetPostStudiosFreshGuestBarrierLockedV31722','no_black=True no_host_wait=True')){
    if($helper.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "Helper contract ausente: $marker"}
}
# V76.0.18.4: these members belong to nested Presenter instances. Referring
# to them from the static partial facade causes CS0103 and is structurally wrong.
foreach($forbidden in @(
    '_hostMovieFramePixels',
    '_hostMovieFrameWidth',
    '_hostMovieFrameHeight',
    '_hostMovieFrameSerial',
    '_hostMovieFramePath',
    '_hostMovieLumaTextureAddress',
    '_hostMovieChromaTextureAddress'
)){
    if($helper.IndexOf($forbidden,[System.StringComparison]::Ordinal) -ge 0){
        throw "Presenter-instance field reference prohibited in static V7618 helper: $forbidden"
    }
}
Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed; hard guest-only Bink contracts passed)."
