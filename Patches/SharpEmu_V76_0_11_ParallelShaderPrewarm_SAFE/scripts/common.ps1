$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.11-PARALLEL-SHADER-PREWARM'
$CacheRel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'
$CachePayloadRel = 'payload\src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'
$CacheV76102Hash = 'f1cff905d31904a870105aba7ae250f796089cd706a21a5f7a7da2d74f2354fe'
$CacheV7611Hash = '09b7daedf5eab60c1979012d6cf125c9a607623e8df5072f6d487c9907ccbbd3'
$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$AgcParallelRel = 'src\SharpEmu.Libs\Agc\AgcExports.ShaderParallelV7611.cs'
$AgcParallelPayloadRel = 'payload\src\SharpEmu.Libs\Agc\AgcExports.ShaderParallelV7611.cs'
$AgcParallelHash = 'cb49dd52696fc1bb15a5a352aa62db19e5e609045471f6efbe67c97653a65331'
$TranslatorRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
$MetalRel = 'src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.cs'
$AtomicHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.AtomicCompatV7609.cs'
$AtomicHelperHash = '4456dafc25323127bf996dccd5b943eb2298282612b0cc1681db2e0078e6cf4d'

function Get-RepoRoot([string]$Preferred) {
    if(Test-Path -LiteralPath (Join-Path $Preferred 'src\SharpEmu.CLI\SharpEmu.CLI.csproj')){ return (Resolve-Path -LiteralPath $Preferred).Path }
    throw "RepositoryRoot invalido: $Preferred"
}
function Get-PatchesRoot([string]$Preferred) {
    if(-not(Test-Path -LiteralPath $Preferred)){New-Item -ItemType Directory -Path $Preferred -Force|Out-Null}
    return (Resolve-Path -LiteralPath $Preferred).Path
}
function Get-Sha256([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Text([string]$Path){ return [System.IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path,[string]$Text){
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Get-OccurrenceCount([string]$Text,[string]$Needle){
    if([string]::IsNullOrEmpty($Needle)){return 0}
    $count=0; $start=0
    while($start -le $Text.Length-$Needle.Length){
        $idx=$Text.IndexOf($Needle,$start,[System.StringComparison]::Ordinal)
        if($idx -lt 0){break}
        $count++; $start=$idx+$Needle.Length
    }
    return $count
}
function Assert-V76102Baseline([string]$RepoRoot){
    $cache=Get-Sha256 (Join-Path $RepoRoot $CacheRel)
    if($cache -ne $CacheV76102Hash -and $cache -ne $CacheV7611Hash){
        throw "Shader cache prerequisite divergente expected=$CacheV76102Hash or $CacheV7611Hash actual=$cache"
    }
    $atomic=Get-Sha256 (Join-Path $RepoRoot $AtomicHelperRel)
    if($atomic -ne $AtomicHelperHash){throw "V76.0.9.3 atomic helper prerequisite mismatch expected=$AtomicHelperHash actual=$atomic"}
    $translator=Read-Text (Join-Path $RepoRoot $TranslatorRel)
    foreach($marker in @('"SClause" or','"SWaitcntDepctr" or','DeclareRdnaAtomicCompatV7609();')){
        if($translator.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.10.2 Vulkan marker ausente: $marker"}
    }
    $metal=Read-Text (Join-Path $RepoRoot $MetalRel)
    if($metal.IndexOf('case "SWaitcntDepctr":',[System.StringComparison]::Ordinal) -lt 0){throw 'V76.0.10.2 Metal SWaitcntDepctr ausente.'}
    if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $AgcRel) -PathType Leaf)){throw "AGC source ausente: $AgcRel"}
}
function Get-AgcParallelStateV7611([string]$RepoRoot){
    $agc=Read-Text (Join-Path $RepoRoot $AgcRel)
    $callCount=Get-OccurrenceCount $agc 'TryCompileGraphicsShaderPairV7611('
    if($callCount -gt 1){throw "AGC parallel call ambiguo occurrences=$callCount"}
    $helperPath=Join-Path $RepoRoot $AgcParallelRel
    $helperHash=Get-Sha256 $helperPath
    if($helperHash -ne '' -and $helperHash -ne $AgcParallelHash){throw "AGC V76.0.11 helper divergente actual=$helperHash"}
    if($callCount -eq 1 -and $helperHash -eq $AgcParallelHash){return 'Applied'}
    if($callCount -eq 1 -and $helperHash -eq ''){return 'ReadyCopyHelper'}
    $start='                    if (!GuestGpu.Current.TryCompilePixelShader('
    $end='                    compiled = (vertexShader!, pixelShader!);'
    if((Get-OccurrenceCount $agc $start) -ne 1){throw 'AGC sequential PS->VS compile anchor ausente/ambiguo.'}
    if((Get-OccurrenceCount $agc $end) -ne 1){throw 'AGC graphics compiled tuple anchor ausente/ambiguo.'}
    return 'ReadySemanticReplace'
}
function Apply-AgcParallelPatchV7611([string]$RepoRoot){
    $path=Join-Path $RepoRoot $AgcRel
    $text=Read-Text $path
    if((Get-OccurrenceCount $text 'TryCompileGraphicsShaderPairV7611(') -eq 1){Write-Host '  = parallel-vs-ps-compile already'; return}
    $startToken='                    if (!GuestGpu.Current.TryCompilePixelShader('
    $endToken='                    compiled = (vertexShader!, pixelShader!);'
    if((Get-OccurrenceCount $text $startToken) -ne 1){throw 'AGC start token invalido para parallel compile.'}
    if((Get-OccurrenceCount $text $endToken) -ne 1){throw 'AGC end token invalido para parallel compile.'}
    $start=$text.IndexOf($startToken,[System.StringComparison]::Ordinal)
    $end=$text.IndexOf($endToken,$start,[System.StringComparison]::Ordinal)
    if($end -le $start){throw 'AGC parallel compile range invalido.'}
    $newline=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
    $lines=@(
        '                    if (!TryCompileGraphicsShaderPairV7611(',
        '                            pixelState,',
        '                            pixelEvaluation,',
        '                            pixelOutputs,',
        '                            exportState,',
        '                            exportEvaluation,',
        '                            guestGlobalBuffers,',
        '                            totalGlobalBuffers,',
        '                            psInputEna,',
        '                            psInputAddr,',
        '                            psInputCntl,',
        '                            requiredVertexOutputCount,',
        '                            out var vertexShader,',
        '                            out var pixelShader,',
        '                            out error))',
        '                    {',
        '                        ReturnPooledEvaluationArrays(exportEvaluation);',
        '                        ReturnPooledEvaluationArrays(pixelEvaluation);',
        '                        return false;',
        '                    }',
        ''
    )
    $replacement=($lines -join $newline)+$newline
    Write-Text $path ($text.Substring(0,$start)+$replacement+$text.Substring($end))
    Write-Host '  * parallel-vs-ps-compile-v7611'
}
function Assert-V7611Installed([string]$RepoRoot){
    $cache=Get-Sha256 (Join-Path $RepoRoot $CacheRel)
    if($cache -ne $CacheV7611Hash){throw "V76.0.11 cache payload mismatch expected=$CacheV7611Hash actual=$cache"}
    $cacheText=Read-Text (Join-Path $RepoRoot $CacheRel)
    foreach($marker in @('ScheduleDiskPrewarmV7611','PrewarmDiskCacheV7611','SHARPEMU_SPIRV_PREWARM_MAX','prewarm_entries=')){
        if($cacheText.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.11 prewarm marker ausente: $marker"}
    }
    $helper=Get-Sha256 (Join-Path $RepoRoot $AgcParallelRel)
    if($helper -ne $AgcParallelHash){throw "V76.0.11 AGC helper mismatch expected=$AgcParallelHash actual=$helper"}
    $agc=Read-Text (Join-Path $RepoRoot $AgcRel)
    if((Get-OccurrenceCount $agc 'TryCompileGraphicsShaderPairV7611(') -ne 1){throw 'V76.0.11 AGC parallel compile call ausente/duplicado.'}
    if($agc.IndexOf('if (!GuestGpu.Current.TryCompilePixelShader(',[System.StringComparison]::Ordinal) -ge 0){throw 'V76.0.11 AGC caminho sequencial antigo ainda presente no callsite principal.'}
}
