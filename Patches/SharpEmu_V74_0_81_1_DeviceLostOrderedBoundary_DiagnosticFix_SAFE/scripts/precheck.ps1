param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$already=$p.Contains('SHARPEMU_V74_0_81_1_DEVICE_LOST_ORDERED_BOUNDARY_FIX')
$riskyStart=$p.Contains('if (!_preservePayloadBatchV7405620)')
$riskyResource=$p.Contains('V74.0.81: keep an already-open payload batch alive while')
$riskyGuard=$p.Contains('if (!useSharedComputeBatchV7405617)')
$burst8=$false;$burst2=$false
$start=$p.IndexOf('private static readonly int _queueSubmissionBurstV74043 =',[System.StringComparison]::Ordinal)
if($start -ge 0){$semi=$p.IndexOf(';',$start,[System.StringComparison]::Ordinal);if($semi -gt $start){$seg=$p.Substring($start,$semi-$start+1);$burst8=($seg -match ':\s*8\s*;');$burst2=($seg -match ':\s*2\s*;')}}
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag v81_1_already=$already"
Write-Host "$script:Tag risky_compute_start_boundary=$riskyStart"
Write-Host "$script:Tag risky_resource_boundary_removed=$riskyResource"
Write-Host "$script:Tag risky_shared_only_flush_guard=$riskyGuard"
Write-Host "$script:Tag burst_default_8=$burst8 burst_default_2=$burst2"
Write-Host "$script:Tag queue_inflight_split_preserved=$($p.Contains('SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT'))"
Write-Host "$script:Tag rigid_sha_gate=False"
if($already){Write-Host "$script:Tag State=AlreadyApplied"}else{Write-Host "$script:Tag State=Ready"}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
