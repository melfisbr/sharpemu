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
if((Get-Sha256 (Join-Path $PackageRoot $CachePayloadRel)) -ne $CacheV7611Hash){throw 'Cache payload V76.0.11.1 hash interno divergente.'}
if((Get-Sha256 (Join-Path $PackageRoot $AgcParallelPayloadRel)) -ne $AgcParallelHash){throw 'AGC parallel helper V76.0.11.1 hash interno divergente.'}
$cache=Read-Text (Join-Path $PackageRoot $CachePayloadRel)
foreach($marker in @('ScheduleDiskPrewarmV7611','PrewarmDiskCacheV7611','SHARPEMU_SPIRV_PREWARM_MAX','Thread.Sleep(100)')){if($cache.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "Contrato prewarm ausente: $marker"}}
$helper=Read-Text (Join-Path $PackageRoot $AgcParallelPayloadRel)
foreach($marker in @('TryCompileGraphicsShaderPairV7611','Task.Run(CompilePixel)','Task.Run(CompileVertex)','SHARPEMU_VK_PARALLEL_STAGE_COMPILE','vertexShader = null;','pixelShader = null;','error = string.Empty;')){if($helper.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "Contrato parallel stage ausente: $marker"}}
$validatorPath=[System.IO.Path]::GetFullPath($PSCommandPath)
foreach($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File){
    if($script.Extension -in '.ps1','.cmd','.md'){
        if([System.IO.Path]::GetFullPath($script.FullName) -eq $validatorPath){continue}
        $body=[System.IO.File]::ReadAllText($script.FullName)
        if($body -match '(?i)Invoke-WebRequest|Start-BitsTransfer|curl\.exe|wget\.exe'){throw "Downloader de rede proibido: $($script.FullName)"}
    }
}
Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; parallel stage + background prewarm + definite-assignment BuildFix contracts passed)."
