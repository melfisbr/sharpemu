. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath=Join-Path $PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'manifest.sha256 ausente'}
$checked=0
foreach($line in Get-Content -LiteralPath $manifestPath){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$'){throw "Linha invalida no manifest: $line"}
    $expected=$Matches[1].ToLowerInvariant(); $relative=$Matches[2].Replace('/','\'); $path=Join-Path $PackageRoot $relative
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Arquivo do manifest ausente: $relative"}
    $actual=Get-Sha256 $path
    if($actual -ne $expected){throw "Hash invalido: $relative expected=$expected actual=$actual"}
    $checked++
}
foreach($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File){
    $tokens=$null; $issues=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$issues)
    if($issues -and $issues.Count -gt 0){throw "PowerShell parse failure em $($script.Name): $(($issues|ForEach-Object{$_.Message}) -join '; ')"}
}
$payload=Join-Path $PackageRoot $CachePayloadRel
if((Get-Sha256 $payload) -ne $CacheNewHash){throw 'Cache payload V76.0.10 hash interno divergente.'}
$text=Read-Text $payload
foreach($marker in @('V76.0.10-r1','IsSemanticShaderEnvironmentV7610','QueueDiskWriteV7610','DrainDiskWritesV7610','ConcurrentQueue<DiskWriteRequestV7610>')){
    if($text.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "Contrato cache V76.0.10 ausente: $marker"}
}
# V76.0.10.1: do not scan this validator against the literal detector tokens it contains.
# validate.ps1 itself is already covered by the package manifest and PowerShell parser above.
$validatorPath=[System.IO.Path]::GetFullPath($PSCommandPath)
foreach($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File){
    if($script.Extension -in '.ps1','.cmd','.md'){
        if([System.IO.Path]::GetFullPath($script.FullName) -eq $validatorPath){continue}
        $body=[System.IO.File]::ReadAllText($script.FullName)
        if($body -match '(?i)Invoke-WebRequest|Start-BitsTransfer|curl\.exe|wget\.exe'){throw "Downloader de rede proibido: $($script.FullName)"}
    }
}
Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; validator self-scan fixed; cache critical-path contracts passed)."
