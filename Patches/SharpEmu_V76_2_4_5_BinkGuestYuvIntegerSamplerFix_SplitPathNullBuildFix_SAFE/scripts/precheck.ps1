. (Join-Path $PSScriptRoot 'common.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$contextPath = Join-Path $PatchesRoot ("SharpEmu_V76_2_4_5_PRECHECK_CONTEXT_{0}.txt" -f $stamp)
try {
    $state = Get-TargetStateV76245
    if ($state -eq 'MissingTarget' -or $state -eq 'MissingScript' -or $state -eq 'MissingRunner') {
        throw "target package incomplete: state=$state target=$TargetRoot"
    }
    Assert-PowerShellParsesV76245 $TargetScript
    $targetText = Read-TextV76245 $TargetScript
    $suspiciousCount = Get-SuspiciousSplitPathCountV76245 $targetText
    $targetHash = Get-Sha256V76245 $TargetScript
    @(
        "Tag=$PackageTag",
        "Target=$TargetRoot",
        "TargetState=$state",
        "PatchTargetSha256=$targetHash",
        "SuspiciousSplitPathNull=$suspiciousCount",
        "Runner=$TargetRunner"
    ) | Set-Content -LiteralPath $contextPath -Encoding UTF8
    Write-Host "$PackageTag Target=$TargetRoot State=$state SuspiciousSplitPathNull=$suspiciousCount"
    Write-Host "$PackageTag PRECHECK PASSED. Context=$contextPath"
}
catch {
    @("ERROR=$($_.Exception.Message)") | Set-Content -LiteralPath $contextPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $contextPath"
}
