. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate_package.ps1"
$s = Write-State
if ($s.ProcessStartInfoRefs -lt 1) { throw "$script:Tag O launcher nao contem ProcessStartInfo; estrutura inesperada." }
if ($s.OldCalls -gt 0) {
    Write-Host "$script:Tag state=needs-ps51-launcher-fix old_calls=$($s.OldCalls)" -ForegroundColor Yellow
} elseif ($s.Marker -and $s.NewCalls -gt 0) {
    Write-Host "$script:Tag state=already-applied new_calls=$($s.NewCalls)" -ForegroundColor Cyan
} else {
    throw "$script:Tag Estado do launcher nao reconhecido; nenhum ArgumentList.Add e nenhum marcador V74.0.77.2.1 completo."
}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
