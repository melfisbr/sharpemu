param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. "$PSScriptRoot\common.ps1"

$repo = Resolve-RepoV74056362 $RepositoryRoot
$hash = Assert-EbootV74056362 $Eboot
Assert-CumulativeV74056362 $repo

$agcPath = Join-Path $repo $script:AgcRelative
$presenterPath = Join-Path $repo $script:PresenterRelative

$agcState = Get-AgcStateV74056362 $repo
$presenterState = Get-PresenterStateV74056362 $repo

Write-Host ('{0} RepositoryRoot={1}' -f $script:Tag, $repo)
Write-Host ('{0} EBOOT_SHA256={1}' -f $script:Tag, $hash)
Write-Host ('{0} AgcSHA256={1} State={2} Ready={3}' -f `
    $script:Tag, `
    (Get-ShaV74056362 $agcPath), `
    $agcState.State, `
    $agcState.Ready)
Write-Host ('{0} PresenterSHA256={1} State={2} ConsiderCount={3}' -f `
    $script:Tag, `
    (Get-ShaV74056362 $presenterPath), `
    $presenterState.State, `
    $presenterState.ConsiderCount)

if ($agcState.State -eq 'Divergent') {
    throw ('{0} PRECHECK REFUSED AGC: {1}' -f $script:Tag, $agcState.Problems)
}

if ($presenterState.State -eq 'Divergent') {
    throw ('{0} PRECHECK REFUSED Presenter: {1}' -f $script:Tag, $presenterState.Problems)
}

Write-Host ('{0} V56.36 parser defect removed.' -f $script:Tag)
Write-Host ('{0} Presenter exact-anchor dependency removed.' -f $script:Tag)
Write-Host ('{0} Existing V76/V76.1/equivalent initialized-image guard is accepted without duplicate insertion.' -f $script:Tag)
Write-Host ('{0} PRECHECK PASSED.' -f $script:Tag) -ForegroundColor Green
