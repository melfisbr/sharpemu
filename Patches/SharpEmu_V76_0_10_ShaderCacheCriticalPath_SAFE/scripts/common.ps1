$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.10-SHADER-CACHE-CRITICAL-PATH'
$CacheRel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'
$CachePayloadRel = 'payload\src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'
$CacheOldHash = '0783a960b89755ce5172598e01bf7d09c0fabdf0841654e4ea4ff572fc83b58f'
$CacheNewHash = 'f1cff905d31904a870105aba7ae250f796089cd706a21a5f7a7da2d74f2354fe'
$AtomicHelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.AtomicCompatV7609.cs'
$AtomicHelperHash = '4456dafc25323127bf996dccd5b943eb2298282612b0cc1681db2e0078e6cf4d'
$TranslatorRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
$MetalRel = 'src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.cs'
$AffectedExistingFiles = @($CacheRel,$TranslatorRel,$MetalRel)

function Get-RepoRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) { $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu' }
    $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    $probe = Join-Path $resolved 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "Repo root invalido: $resolved" }
    return $resolved
}
function Get-PatchesRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) { $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches' }
    if (-not (Test-Path -LiteralPath $RequestedRoot -PathType Container)) { New-Item -ItemType Directory -Path $RequestedRoot -Force | Out-Null }
    return [System.IO.Path]::GetFullPath($RequestedRoot)
}
function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Arquivo ausente: $Path" }
    return [System.IO.File]::ReadAllText($Path)
}
function Write-Text {
    param([string]$Path,[string]$Text)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Text,$utf8NoBom)
}
function Get-OccurrenceCount {
    param([string]$Text,[string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count=0; $start=0
    while ($start -le $Text.Length-$Needle.Length) {
        $idx=$Text.IndexOf($Needle,$start,[System.StringComparison]::Ordinal)
        if ($idx -lt 0) { break }
        $count++; $start=$idx+$Needle.Length
    }
    return $count
}
function Replace-OnceRequired {
    param([string]$Path,[string]$Old,[string]$New,[string]$Marker,[string]$Label)
    $text=Read-Text $Path
    if ($text.IndexOf($Marker,[System.StringComparison]::Ordinal) -ge 0) {
        Write-Host "  = $Label already"
        return
    }
    $count=Get-OccurrenceCount $text $Old
    if ($count -ne 1) { throw "Anchor invalida para $Label em $Path occurrences=$count" }
    $idx=$text.IndexOf($Old,[System.StringComparison]::Ordinal)
    Write-Text $Path ($text.Substring(0,$idx)+$New+$text.Substring($idx+$Old.Length))
    Write-Host "  * $Label"
}
function Assert-V76093Baseline {
    param([string]$RepoRoot)
    $atomic=Get-Sha256 (Join-Path $RepoRoot $AtomicHelperRel)
    if ($atomic -ne $AtomicHelperHash) { throw "V76.0.9.3 helper prerequisite mismatch expected=$AtomicHelperHash actual=$atomic" }
    $translator=Read-Text (Join-Path $RepoRoot $TranslatorRel)
    if ($translator.IndexOf('DeclareRdnaAtomicCompatV7609();',[System.StringComparison]::Ordinal) -lt 0 -or
        $translator.IndexOf('EmitRdnaBoundedAtomicV7609(',[System.StringComparison]::Ordinal) -lt 0) {
        throw 'V76.0.9.3 atomic markers ausentes no translator.'
    }
    $cacheHash=Get-Sha256 (Join-Path $RepoRoot $CacheRel)
    if ($cacheHash -ne $CacheOldHash -and $cacheHash -ne $CacheNewHash) {
        throw "Shader cache helper divergente: expected old=$CacheOldHash or new=$CacheNewHash actual=$cacheHash"
    }
}
function Assert-V7610Installed {
    param([string]$RepoRoot)
    $cache=Join-Path $RepoRoot $CacheRel
    $hash=Get-Sha256 $cache
    if ($hash -ne $CacheNewHash) { throw "V76.0.10 cache payload mismatch expected=$CacheNewHash actual=$hash" }
    $cacheText=Read-Text $cache
    foreach ($marker in @(
        'CacheVersion = "V76.0.10-r1"',
        'IsSemanticShaderEnvironmentV7610',
        'QueueDiskWriteV7610',
        'DrainDiskWritesV7610',
        'ShaderCache", "V76.0.10"')) {
        if ($cacheText.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0) { throw "V76.0.10 cache marker ausente: $marker" }
    }
    $translator=Read-Text (Join-Path $RepoRoot $TranslatorRel)
    if ($translator.IndexOf('"SClause" or',[System.StringComparison]::Ordinal) -lt 0 -or
        $translator.IndexOf('"SWaitcntDepctr" or',[System.StringComparison]::Ordinal) -lt 0) {
        throw 'V76.0.10 Vulkan SOPP no-op coverage incompleta.'
    }
    $metal=Read-Text (Join-Path $RepoRoot $MetalRel)
    if ($metal.IndexOf('case "SWaitcntDepctr":',[System.StringComparison]::Ordinal) -lt 0) {
        throw 'V76.0.10 Metal SWaitcntDepctr carry parity ausente.'
    }
}
