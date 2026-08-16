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

$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

if($ph -ne '0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8'){
    throw "Presenter baseline changed; expected 0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8, got $ph"
}
if($ah -ne '7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE'){
    throw "AgcExports baseline changed; expected 7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE, got $ah"
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "Unexpected EBOOT SHA256: $eh"
}

$pt=[IO.File]::ReadAllText($presenter)
$at=[IO.File]::ReadAllText($agc)

foreach($marker in @(
    'TryBuildUntrackedTextureProbe',
    'MarkTextureContentCached',
    'SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19'
)){
    if(-not $pt.Contains($marker)){
        throw "Presenter expected marker missing: $marker"
    }
}

foreach($marker in @(
    'TryResolveDccMetadataAlias',
    'TryCreateGuestDrawTexture',
    'residentMatches',
    'RenderTargetWriters',
    'gpuWriterPending',
    'MetadataAddress'
)){
    if(-not $at.Contains($marker)){
        throw "AgcExports expected marker missing: $marker"
    }
}

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "AgcExports SHA256: $ah"
Write-Host '[V73.0.20.4] PRECHECK PASSED. Exact current baseline locked.' -ForegroundColor Green
