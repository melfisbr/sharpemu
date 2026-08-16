param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Resolve-RepoRootV730221 -RepositoryRoot $RepositoryRoot
$agc=Get-AgcPathV730221 -Root $repo
$presenter=Get-PresenterPathV730221 -Root $repo

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "[V73.0.22.1] EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "[V73.0.22.1] EBOOT SHA256 mismatch: $eh"
}

$text=[IO.File]::ReadAllText($agc)
$state=Get-CompositeMergeStateV730221 -Text $text
$hash=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

if($state -eq 'Baseline' -and $hash -ne 'BEC6107EF646A8D53CB5276F2B8ED29FA818403F4B1488E0D5B199B2D1EA82D1'){
    $capture=New-AgcCaptureV730221 `
        -Root $repo `
        -AgcPath $agc `
        -Reason "unexpected-baseline-hash-$hash"
    throw "[V73.0.22.1] AGC changed again. Capture: $capture"
}

if($state -ne 'Baseline' -and $state -ne 'Applied'){
    $capture=New-AgcCaptureV730221 `
        -Root $repo `
        -AgcPath $agc `
        -Reason $state
    throw "[V73.0.22.1] Unsupported AGC replay structure. Capture: $capture"
}

if($state -eq 'Baseline'){
    $dry=Convert-AgcCompositeMergeV730221 -Text $text
    $dryHash=Get-Utf8Sha256V730221 -Text $dry

    if((Get-CompositeMergeStateV730221 -Text $dry) -ne 'Applied'){
        throw '[V73.0.22.1] Same-transformer dry-run failed.'
    }

    $lineDelta=
        ($dry.Split("`n").Count - $text.Split("`n").Count)
    if($lineDelta -ne 4){
        throw "[V73.0.22.1] Unexpected dry-run line delta: $lineDelta"
    }

    Write-Host "[V73.0.22.1] DRY-RUN PASSED: exactly two replay conditions changed." -ForegroundColor Green
    Write-Host "[V73.0.22.1] Candidate UTF8 SHA256: $dryHash"
} else {
    Write-Host '[V73.0.22.1] Composite merge already applied.' -ForegroundColor Yellow
}

$presenterHash=if([IO.File]::Exists($presenter)){
    (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
} else {
    'missing'
}

Write-Host "[V73.0.22.1] AGC SHA256: $hash"
Write-Host "[V73.0.22.1] AGC state: $state"
Write-Host "[V73.0.22.1] Presenter SHA256: $presenterHash"
Write-Host "[V73.0.22.1] V74.0.25 marker preserved: $($text.Contains('SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION'))"
Write-Host '[V73.0.22.1] PRECHECK PASSED.' -ForegroundColor Green
