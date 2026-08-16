param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. ([IO.Path]::Combine($PSScriptRoot,'common.ps1'))

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=Resolve-SourceBase $repo
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "Unexpected EBOOT SHA256: $eh"
}

Require-ReplaySwitch $agc

$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "AgcExports SHA256: $ah"
Write-Host 'Targetless replay switch: present'
Write-Host 'PendingTargetlessDraws path: present'
Write-Host '[V73.0.21.2] PRECHECK PASSED. No source mutation will be performed.' -ForegroundColor Green
