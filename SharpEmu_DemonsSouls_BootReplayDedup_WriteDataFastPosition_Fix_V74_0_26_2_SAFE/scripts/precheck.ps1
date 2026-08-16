param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Resolve-RepoV740262 -RepositoryRoot $RepositoryRoot
$agcPath=Get-AgcV740262 -Root $root
$hostMoviePath=Get-HostMovieV740262 -Root $root
$packageRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$payload=[IO.Path]::Combine(
    $packageRoot,'payload','SharpEmu.Libs','Agc','AgcExports.cs')

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "[V74.0.26.2] EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "[V74.0.26.2] EBOOT SHA256 mismatch: $eh"
}

$ah=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
$payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
if($payloadHash -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){
    throw "[V74.0.26.2] AGC payload hash invalid: $payloadHash"
}
if($ah -ne 'C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC' -and $ah -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){
    throw "[V74.0.26.2] AGC changed since the uploaded V73.0.22.1 result: $ah"
}

$agcText=[IO.File]::ReadAllText($agcPath)
if($ah -eq 'C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC'){
    $normalized=$agcText.Replace("`r`n","`n")
    $old=@'
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
    if(([regex]::Matches($normalized,[regex]::Escape($old))).Count -ne 1){
        throw '[V74.0.26.2] AGC exact dry-run anchor count is not 1.'
    }
    Write-Host '[V74.0.26.2] AGC DRY-RUN PASSED: exact V74.0.25 branch located once.' -ForegroundColor Green
} else {
    if(-not $agcText.Contains('SHARPEMU_V74_0_26_WRITE_DATA_NO_GPU_READBACK')){
        throw '[V74.0.26.2] Corrected AGC hash present but V74.0.26 marker missing.'
    }
    Write-Host '[V74.0.26.2] AGC correction already installed.' -ForegroundColor Yellow
}

$mediaText=[IO.File]::ReadAllText($hostMoviePath)
if(-not(Test-MediaReplayDedupeV740262 -Text $mediaText)){
    throw '[V74.0.26.2] HostMovieBridge does not contain the complete existing V31.7.9 replay-dedupe capability.'
}

Write-Host '[V74.0.26.2] MEDIA CAPABILITY PASSED: existing V31.7.9 dedupe detected; source will NOT be modified.' -ForegroundColor Green
Write-Host "[V74.0.26.2] HostMovieBridge SHA256: $((Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash)"
Write-Host "[V74.0.26.2] AGC SHA256: $ah"
Write-Host "[V74.0.26.2] AGC target: BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804"
Write-Host "[V74.0.26.2] EBOOT SHA256 OK: $eh"
Write-Host '[V74.0.26.2] PRECHECK PASSED.' -ForegroundColor Green
