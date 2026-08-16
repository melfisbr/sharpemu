param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=$null
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $vp=[IO.Path]::Combine(
        $candidate,
        'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $ag=[IO.Path]::Combine(
        $candidate,
        'SharpEmu.Libs\Agc\AgcExports.cs')
    if([IO.File]::Exists($vp) -and [IO.File]::Exists($ag)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$presenter=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\Agc\AgcExports.cs')

$pt=[IO.File]::ReadAllText($presenter)
$at=[IO.File]::ReadAllText($agc)

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19',
    'TryBuildUntrackedTextureProbe',
    'ComputeSparseGuestContentProbe',
    '_untrackedTextureCacheProbes'
)){
    if(-not $pt.Contains($marker)){
        throw "V73.0.19.x presenter prerequisite missing: $marker"
    }
}

foreach($marker in @(
    'TryResolveDccMetadataAlias',
    'TryCreateGuestDrawTexture',
    'RenderTargetWriters',
    'gpuWriterPending',
    'MetadataAddress'
)){
    if(-not $at.Contains($marker)){
        throw "DCC/AGC structural prerequisite missing: $marker"
    }
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "Unexpected EBOOT SHA256: $eh"
}

$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "AgcExports SHA256: $ah"

if($pt.Contains('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20') -and
   $at.Contains('SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20')){
    Write-Host '[V73.0.20] Corrections already present.' -ForegroundColor Yellow
}

Write-Host '[V73.0.20] PRECHECK PASSED.' -ForegroundColor Green
