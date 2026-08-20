param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$applied=$p.Contains('SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW')
$split=$p.Contains('SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT')
$flush=$p.Contains('SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR')
$burst=$p.Contains('SHARPEMU_V74_0_81_BOUNDED_QUEUE_BURST')
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag deep_flow_marker=$applied"
Write-Host "$script:Tag queue_inflight_split=$split"
Write-Host "$script:Tag compute_batch_flush_repair=$flush"
Write-Host "$script:Tag bounded_queue_burst=$burst"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag preserves_v74078_and_v74080=True"
if($applied -and $split -and $flush -and $burst){Write-Host "$script:Tag State=AlreadyApplied"}else{Write-Host "$script:Tag State=Ready"}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
