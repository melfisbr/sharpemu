param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. ([IO.Path]::Combine($PSScriptRoot,'common.ps1'))

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=Resolve-SourceBase $repo
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')
$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw "EBOOT missing: $Eboot"}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){throw "Unexpected EBOOT SHA256: $eh"}

$src=[IO.File]::ReadAllText($presenter)
try {
    $dry=New-PatchedPresenter $src
} catch {
    $capture=New-SourceCapture $repo $base ('precheck-structure-failed: '+$_.Exception.Message)
    throw "V73.0.21.1 PRECHECK structure failed. Exact current source captured to: $capture"
}

# This package intentionally accepts exactly the hash reported by the user's
# failed V73.0.21 PRECHECK, or an already-satisfied newer source.
if($ph -ne '2902CDEA16B5134061B2722EF68CB8A97FCA7D33FCDA2538AD4BB14420AC17E5' -and $dry.Changed) {
    $capture=New-SourceCapture $repo $base "unexpected-presenter-hash-$ph"
    throw "Presenter changed again: $ph. Exact current source captured to: $capture"
}

$agcText=[IO.File]::ReadAllText($agc)
if($agcText.IndexOf('SHARPEMU_REPLAY_TARGETLESS_COMPOSITES',[StringComparison]::Ordinal) -lt 0) {
    $capture=New-SourceCapture $repo $base 'targetless-replay-switch-missing'
    throw "Current AgcExports no longer exposes SHARPEMU_REPLAY_TARGETLESS_COMPOSITES. Capture: $capture"
}

$tmp=[IO.Path]::Combine([IO.Path]::GetTempPath(),"SharpEmu_V73_0_21_1_dry_$([Guid]::NewGuid().ToString('N')).cs")
try {
    Write-Utf8NoBom $tmp $dry.Text
    $dryHash=(Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
Write-Host "Presenter SHA256: $ph"
Write-Host "Dry-run action: $($dry.Reason)"
Write-Host "Dry-run SHA256: $dryHash"
Write-Host "Targetless replay switch: present"
Write-Host '[V73.0.21.1] PRECHECK PASSED.' -ForegroundColor Green
