param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=$null
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $ag=[IO.Path]::Combine($candidate,'SharpEmu.Libs\Agc\AgcExports.cs')
    $vp=[IO.Path]::Combine($candidate,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    if([IO.File]::Exists($ag) -and [IO.File]::Exists($vp)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$payload=[IO.Path]::Combine($pkg,'payload\SharpEmu.Libs\Agc\AgcExports.cs')

$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash

if($payloadHash -ne '2A68E4F9E3BBAACC50409D03EB146235546392A8F036C8628D5CF6B2560E4DE1') {
    throw "Payload hash invalid: $payloadHash"
}

$already=$ah -eq '2A68E4F9E3BBAACC50409D03EB146235546392A8F036C8628D5CF6B2560E4DE1'
if(-not $already -and $ah -ne '7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE') {
    throw "AgcExports changed since successful V73.0.21.2 A/B: $ah"
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E') {
    throw "Unexpected EBOOT SHA256: $eh"
}

$pt=[IO.File]::ReadAllText($presenter)
$largeProbePresent=
    $pt.Contains('V74.0.23.1') -and
    $pt.Contains('ARRAY_BASELINE') -and
    $pt.Contains('V740231MaxLargeArraySparseProbeBytes')

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "AgcExports SHA256: $ah"
Write-Host "Presenter SHA256: $ph"
Write-Host "Payload SHA256: $payloadHash"
Write-Host "V74.0.23.1 large-array sparse probe present: $largeProbePresent"
Write-Host '[V73.0.22] PRECHECK PASSED: exact AGC baseline/payload verified.' -ForegroundColor Green
