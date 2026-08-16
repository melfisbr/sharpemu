param([string]$RepositoryRoot="",[string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoV74026 -RepositoryRoot $RepositoryRoot
$agc=Get-AgcV74026 -Root $root
$hostMoviePath=Get-HostMovieV74026 -Root $root
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$payload=[IO.Path]::Combine($pkg,'payload','SharpEmu.Libs','Agc','AgcExports.cs')

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){throw "[V74.0.26.1] EBOOT missing: $Eboot"}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){throw "[V74.0.26.1] EBOOT SHA256 mismatch: $eh"}

$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$ph=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
if($ph -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){throw "[V74.0.26.1] Payload hash invalid: $ph"}
if($ah -ne 'C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC' -and $ah -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){throw "[V74.0.26.1] AGC changed since uploaded result: $ah"}

if($ah -eq 'C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC'){
    $t=[IO.File]::ReadAllText($agc).Replace("`r`n","`n")
    $a=@'
        var packetPositionWriteV74025 =
            !requiresGpuBufferReadback && _writeDataPacketPositionV74025;
        var orderedSequence = requiresGpuBufferReadback || packetPositionWriteV74025
            ? GuestGpu.Current.SubmitOrderedGuestAction(
                ApplyAndQueueCompletion,
                debugName)
            : GuestGpu.Current.SubmitOrderedGuestActionAfterQueueCompletion(
                ApplyAndQueueCompletion,
                debugName);
'@.TrimEnd()
    if(([regex]::Matches($t,[regex]::Escape($a))).Count -ne 1){throw '[V74.0.26.1] AGC exact dry-run anchor count != 1.'}
    Write-Host '[V74.0.26.1] AGC DRY-RUN PASSED.' -ForegroundColor Green
} else {
    Write-Host '[V74.0.26.1] AGC already corrected.' -ForegroundColor Yellow
}

$ht=[IO.File]::ReadAllText($hostMoviePath)
$ms=Get-MediaDedupeStateV74026 -Text $ht
if($ms -eq 'Baseline'){
    $dry=Convert-MediaDedupeV74026 -Text $ht
    if((Get-MediaDedupeStateV74026 -Text $dry) -ne 'Applied'){throw '[V74.0.26.1] Media dry-run failed.'}
    Write-Host '[V74.0.26.1] MEDIA DRY-RUN PASSED.' -ForegroundColor Green
} elseif($ms -eq 'Applied'){
    Write-Host '[V74.0.26.1] Media dedupe default already present.' -ForegroundColor Yellow
} else {
    throw "[V74.0.26.1] HostMovieBridge structure unsupported: $ms"
}
Write-Host "[V74.0.26.1] EBOOT SHA256 OK: $eh"
Write-Host "[V74.0.26.1] AGC SHA256: $ah"
Write-Host "[V74.0.26.1] AGC target: BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804"
Write-Host "[V74.0.26.1] Media state: $ms"
Write-Host '[V74.0.26.1] PRECHECK PASSED.' -ForegroundColor Green
