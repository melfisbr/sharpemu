param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=$null
foreach($c in @([IO.Path]::Combine($repo,'src'),$repo)){
    $presenter=[IO.Path]::Combine($c,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $agc=[IO.Path]::Combine($c,'SharpEmu.Libs\Agc\AgcExports.cs')
    if([IO.File]::Exists($presenter) -and [IO.File]::Exists($agc)){
        $base=$c
        break
    }
}
if($null -eq $base){throw 'Source layout nao reconhecido.'}

$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
$kernel=[IO.Path]::Combine($base,'SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs')
$ampr=[IO.Path]::Combine($base,'SharpEmu.Libs\Ampr\AmprExports.cs')

if(-not [IO.File]::Exists($kernel)){throw 'KernelMemoryCompatExports.cs missing.'}
$kernelText=[IO.File]::ReadAllText($kernel)
if(-not $kernelText.Contains('IsConfiguredApplicationTitle(string titleId)')){
    throw 'V73.0.13 title-scoped application identity helper missing.'
}
if(-not $kernelText.Contains('TryReadTrackedLibcHeapGpuAlias')){
    throw 'GPU alias heap reader missing.'
}

if(-not [IO.File]::Exists($ampr) -or
   -not [IO.File]::ReadAllText($ampr).Contains('SHARPEMU_DEMONSSOULS_EBOOT_APR_DEFERRED_READ_V73_0_16')){
    throw 'V73.0.16 APR deferred resource read prerequisite missing.'
}

$ptext=[IO.File]::ReadAllText($presenter)
$atext=[IO.File]::ReadAllText($agc)
$knownPresenterHash='B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245'
$knownAgcHash='9951870F2D0ED6C66F0743F87780F6981A3ECA46B27BB4BA95FD0784E9DA5C98'
$currentPresenterHash=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$currentAgcHash=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

if($currentPresenterHash -eq $knownPresenterHash -and
   $currentAgcHash -eq $knownAgcHash){
    Write-Host '[V73.0.19.1] Exact accumulated UI/GPU baseline recognized.' -ForegroundColor Cyan
}

$already=$ptext.Contains('SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19') -and
         $atext.Contains('SHARPEMU_DEMONSSOULS_UI_RT_ALIAS_READ_V73_0_19')

if(-not $already){
    foreach($anchor in @(
        '_cachedTextureIdentities = new();',
        'internal static bool IsTextureContentCached',
        'private TextureResource GetOrCreateCachedTextureResource',
        'private static byte[]? TryReadGuestTexturePixels',
        'ComputeSparseGuestContentProbe',
        'MarkTextureContentCached(key);'
    )){
        if(-not $ptext.Contains($anchor)){throw "Presenter structural anchor missing: $anchor"}
    }
    foreach($anchor in @(
        'ProvideRenderTargetInitialData',
        'var readOk = ctx.Memory.TryRead(target.Address, initialData);',
        'TryReadTextureGuestMemory'
    )){
        if(-not $atext.Contains($anchor)){throw "AGC structural anchor missing: $anchor"}
    }
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw "EBOOT missing: $Eboot"}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){throw "EBOOT differs from audited PPSA01341: $eh"}

$ph=$currentPresenterHash
$ah=$currentAgcHash
Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "AgcExports SHA256: $ah"
Write-Host "V73.0.17 queue-local marker present: $($ptext.Contains('SHARPEMU_QUEUE_LOCAL_VISIBILITY_V73_0_17'))"
if($already){Write-Host '[V73.0.19.1] UI texture fix already present.' -ForegroundColor Yellow}
Write-Host '[V73.0.19.1] PRECHECK PASSED.' -ForegroundColor Green
