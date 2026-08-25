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
    $tokens=$null
    $issues=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$issues)
    if($issues -and $issues.Count -gt 0){
        throw "PowerShell parse failure em $($script.Name): $(($issues|ForEach-Object{$_.Message}) -join '; ')"
    }
}

if((Get-Sha256 (Join-Path $PackageRoot $HelperPayloadRel)) -ne $HelperExpectedHashV7612){
    throw 'Bink YUV helper V76.0.12.3 hash interno divergente.'
}
$helper=Read-Text (Join-Path $PackageRoot $HelperPayloadRel)
foreach($marker in @(
    'using SharpEmu.Libs.Gpu;',
    'IsCurrentGuestBinkYuvProducerV7612',
    'MarkGuestBinkYuvProducerV7612',
    'ShouldSuppressGuestBinkStorageCpuUploadV7612',
    'reset-producer-registry',
    'not-written-in-current-bink-session',
    'gpu-authoritative-producer'
)){
    if($helper.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){
        throw "Contrato Bink YUV V76.0.12.3 ausente: $marker"
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

Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; Bink guest YUV epoch/storage contracts passed)."
