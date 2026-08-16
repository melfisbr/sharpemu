param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Find-DefinitionLine {
    param([string]$Text,[string]$Name)
    $escaped=[Text.RegularExpressions.Regex]::Escape($Name)
    $pattern=
        '(?m)^[ \t]*(?:private|internal|public|protected)\s+' +
        '(?:(?:static|unsafe|sealed|virtual|override|new|async)\s+)*' +
        '[A-Za-z_][A-Za-z0-9_<>,\.\?\[\]\s]*\b' +
        $escaped +
        '\s*\('
    $matches=[Text.RegularExpressions.Regex]::Matches($Text,$pattern)
    if($matches.Count -ne 1){
        throw "Definition $Name expected once; found $($matches.Count)."
    }
    $end=$Text.IndexOf("`n",$matches[0].Index)
    if($end -lt 0){$end=$Text.Length}
    return $Text.Substring($matches[0].Index,$end-$matches[0].Index).Trim()
}

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
$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

$already=
    $pt.Contains('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_2') -and
    $at.Contains('SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_2')

if(-not $already){
    if($ph -ne '0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8'){
        throw "Unexpected presenter baseline: $ph"
    }
    if($ah -ne '7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE'){
        throw "Unexpected AgcExports baseline: $ah"
    }
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19',
    'TryBuildUntrackedTextureProbe',
    'MarkTextureContentCached'
)){
    if(-not $pt.Contains($marker)){
        throw "Presenter prerequisite missing: $marker"
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
        throw "AGC prerequisite missing: $marker"
    }
}

$resolveLine=Find-DefinitionLine $at 'TryResolveDccMetadataAlias'
$createLine=Find-DefinitionLine $at 'TryCreateGuestDrawTexture'

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "Unexpected EBOOT SHA256: $eh"
}

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "AgcExports SHA256: $ah"
Write-Host "Resolve definition: $resolveLine" -ForegroundColor DarkCyan
Write-Host "Texture definition: $createLine" -ForegroundColor DarkCyan
if($already){
    Write-Host '[V73.0.20.2] Already applied.' -ForegroundColor Yellow
}
Write-Host '[V73.0.20.2] PRECHECK PASSED.' -ForegroundColor Green
