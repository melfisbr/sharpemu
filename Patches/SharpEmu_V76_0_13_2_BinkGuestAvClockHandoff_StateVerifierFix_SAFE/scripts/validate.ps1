. (Join-Path $PSScriptRoot 'common.ps1')

$manifestPath=Join-Path $PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'manifest.sha256 ausente'}
$checked=0
foreach($line in Get-Content -LiteralPath $manifestPath){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$'){throw "Linha invalida no manifest: $line"}
    $expected=$Matches[1].ToLowerInvariant()
    $relative=$Matches[2].Replace('/','\')
    $path=Join-Path $PackageRoot $relative
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Arquivo do manifest ausente: $relative"}
    $actual=Get-Sha256 $path
    if($actual -ne $expected){throw "Hash invalido: $relative expected=$expected actual=$actual"}
    $checked++
}

foreach($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File){
    $tokens=$null; $issues=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$issues)
    if($issues -and $issues.Count -gt 0){
        throw "PowerShell parse failure em $($script.Name): $(($issues|ForEach-Object{$_.Message}) -join '; ')"
    }
}

$helperPath=Join-Path $PackageRoot $AvHelperPayloadRel
if((Get-Sha256 $helperPath) -ne $AvHelperExpectedHashV7613){
    throw 'V76.0.13.2 A/V helper hash interno divergente.'
}
$helper=Read-Text $helperPath
foreach($marker in @(
    'using SharpEmu.HLE.Host;',
    'BinkGuestAvClockV7613',
    'ShouldHoldFirstVisual',
    'NotifyPresentedFrame',
    'GuestAudioClock.PlayedSeconds',
    'action=neutral-yuv-no-render-thread-wait',
    'producer_generation='
)){
    if($helper.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){
        throw "Contrato V76.0.13.2 A/V helper ausente: $marker"
    }
}

$validatorPath=[System.IO.Path]::GetFullPath($PSCommandPath)
foreach($file in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File){
    if($file.Extension -in '.ps1','.cmd','.md'){
        if([System.IO.Path]::GetFullPath($file.FullName) -eq $validatorPath){continue}
        $body=[System.IO.File]::ReadAllText($file.FullName)
        if($body -match '(?i)Invoke-WebRequest|Start-BitsTransfer|curl\.exe|wget\.exe'){
            throw "Downloader de rede proibido: $($file.FullName)"
        }
    }
}

Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; guest A/V handoff contracts passed)."
