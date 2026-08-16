param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-TextSha256([string]$Text){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $hash=$sha.ComputeHash($bytes)
        return (($hash | ForEach-Object {$_.ToString('X2')}) -join '')
    } finally {
        $sha.Dispose()
    }
}

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=$null
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $vp=[IO.Path]::Combine($candidate,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $ag=[IO.Path]::Combine($candidate,'SharpEmu.Libs\Agc\AgcExports.cs')
    if([IO.File]::Exists($vp) -and [IO.File]::Exists($ag)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
$payload=[IO.Path]::Combine(
    [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..')),
    'payload\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')

$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash

if($ah -ne '7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE'){
    throw "AgcExports changed since exact capture: $ah"
}
if($payloadHash -ne '1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385'){
    throw "Payload hash invalid: $payloadHash"
}

$already=$ph -eq '1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385'
if(-not $already -and $ph -ne '0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8'){
    throw "Presenter changed since exact capture: $ph"
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "Unexpected EBOOT SHA256: $eh"
}

if(-not $already){
    # Full dry-run on the exact current source. APPLY is not allowed unless the
    # in-memory transformation produces byte-for-byte the shipped payload hash.
    $src=[IO.File]::ReadAllText($presenter)
    $old=@'
        probe = default;
        if (texture.Address == 0 ||
            byteCount == 0 ||
            byteCount > MaxTrackedGuestImageBytes)
        {
            return false;
        }
'@
    $new=@'
        probe = default;
        // SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21
        // This function samples at most 8 x 64 bytes. Logical resource size is
        // therefore not a reason to disable the probe: rejecting a 320 MiB
        // array leaves it without a baseline and forces cache churn/reuploads.
        if (texture.Address == 0 ||
            byteCount == 0)
        {
            return false;
        }
'@

    $count=([Text.RegularExpressions.Regex]::Matches(
        $src,[Text.RegularExpressions.Regex]::Escape($old))).Count
    if($count -ne 1){
        throw "DRY-RUN failed: exact probe block count=$count"
    }
    $dry=$src.Replace($old,$new)
    $dryHash=Get-TextSha256 $dry
    if($dryHash -ne '1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385'){
        throw "DRY-RUN hash mismatch: expected 1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385, got $dryHash"
    }
    if(-not $dry.Contains('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21')){
        throw 'DRY-RUN marker missing.'
    }
    Write-Host "[V73.0.21] DRY-RUN PASSED: exact source -> exact payload SHA256 $dryHash" -ForegroundColor Green
} else {
    Write-Host '[V73.0.21] Presenter already patched; payload hash matches.' -ForegroundColor Yellow
}

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "AgcExports SHA256: $ah"
Write-Host "Payload SHA256: $payloadHash"
Write-Host '[V73.0.21] PRECHECK PASSED.' -ForegroundColor Green
