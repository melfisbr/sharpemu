param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Resolve-RepoV740263 -RepositoryRoot $RepositoryRoot
$agcPath=Get-AgcPathV740263 -Root $root
$hostMoviePath=Get-HostMoviePathV740263 -Root $root

$packageRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$payload=[IO.Path]::Combine(
    $packageRoot,'payload','SharpEmu.Libs','Agc','AgcExports.cs')

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "[V74.0.26.3] EBOOT missing: $Eboot"
}
$ebootHash=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($ebootHash -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "[V74.0.26.3] EBOOT SHA256 mismatch: $ebootHash"
}

$agcHash=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
$payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
$hostHash=(Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash

if($payloadHash -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){
    throw "[V74.0.26.3] AGC payload hash invalid: $payloadHash"
}

if($agcHash -ne 'C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC' -and $agcHash -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){
    $capture=New-SourceCaptureV740263 `
        -Root $root `
        -AgcPath $agcPath `
        -HostMoviePath $hostMoviePath `
        -Reason "unexpected-agc-$agcHash"
    throw "[V74.0.26.3] AGC changed again. Exact source captured: $capture"
}

$agcText=[IO.File]::ReadAllText($agcPath)

if($agcHash -eq 'C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC'){
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
        $capture=New-SourceCaptureV740263 `
            -Root $root `
            -AgcPath $agcPath `
            -HostMoviePath $hostMoviePath `
            -Reason 'agc-anchor-count-not-one'
        throw "[V74.0.26.3] Exact AGC branch no longer matches. Source captured: $capture"
    }

    Write-Host '[V74.0.26.3] AGC DRY-RUN PASSED: exact V74.0.25 packet-position branch located once.' -ForegroundColor Green
} else {
    if(-not $agcText.Contains('SHARPEMU_V74_0_26_WRITE_DATA_NO_GPU_READBACK')){
        throw '[V74.0.26.3] Corrected AGC hash present but marker missing.'
    }
    Write-Host '[V74.0.26.3] AGC correction already installed.' -ForegroundColor Yellow
}

# Media is deliberately not pattern-matched or patched anymore.
# The latest guest-owned JobPool result already proved AUTO_BOOT=OFF can let the
# EBOOT naturally request ps_studios_logo.bk2 exactly once.
Write-Host '[V74.0.26.3] MEDIA PRECHECK: HostMovieBridge exists and will remain READ-ONLY.' -ForegroundColor Green
Write-Host '[V74.0.26.3] Runtime strategy: guest-owned movies (SHARPEMU_BINK_AUTO_BOOT=0); no replay-dedupe dependency.' -ForegroundColor Green
Write-Host "[V74.0.26.3] HostMovieBridge SHA256: $hostHash"
Write-Host "[V74.0.26.3] AGC SHA256: $agcHash"
Write-Host "[V74.0.26.3] AGC target: BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804"
Write-Host "[V74.0.26.3] EBOOT SHA256 OK: $ebootHash"
Write-Host '[V74.0.26.3] PRECHECK PASSED.' -ForegroundColor Green
