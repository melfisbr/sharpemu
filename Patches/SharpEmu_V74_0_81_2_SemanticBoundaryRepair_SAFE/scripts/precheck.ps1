param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$already=$p.Contains('SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
$startBoundary=$p.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY')
$resourceBoundary=$p.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY')
$riskyStart=$p.Contains('if (!_preservePayloadBatchV7405620)')
$riskyResource=$p.Contains('V74.0.81: keep an already-open payload batch alive while')
$riskyGuard=$p.Contains('if (!useSharedComputeBatchV7405617)')
$burst8=$false;$burst2=$false
$start=$p.IndexOf('private static readonly int _queueSubmissionBurstV74043 =',[System.StringComparison]::Ordinal)
if($start -ge 0){$semi=$p.IndexOf(';',$start,[System.StringComparison]::Ordinal);if($semi -gt $start){$bseg=$p.Substring($start,$semi-$start+1);$burst8=($bseg -match ':\s*8\s*;');$burst2=($bseg -match ':\s*2\s*;')}}
$methodMatch=[regex]::Match($p,'(?m)^\s*private\s+void\s+ExecuteComputeDispatchCore\s*\(\s*VulkanComputeGuestDispatch\s+work\s*\)\s*\{')
if(-not $methodMatch.Success){throw "$script:Tag ExecuteComputeDispatchCore semantic signature missing during precheck."}
$mStart=$methodMatch.Index
$tail=$p.Substring($mStart+$methodMatch.Length)
$nextMatch=[regex]::Match($tail,'(?m)^\s*private\s+void\s+TraceDeviceLostCandidateV74056\s*\(')
if(-not $nextMatch.Success){throw "$script:Tag TraceDeviceLostCandidateV74056 boundary missing during precheck."}
$mEnd=$mStart+$methodMatch.Length+$nextMatch.Index
$seg=$p.Substring($mStart,$mEnd-$mStart)
$resourceCalls=([regex]::Matches($seg,'CreateComputeDispatchResources\s*\(\s*work\s*\)')).Count
$flushes=([regex]::Matches($seg,'FlushBatchedGuestCommands\s*\(\s*\)\s*;')).Count
Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag v81_2_already=$already"
Write-Host "$script:Tag semantic_start_boundary=$startBoundary"
Write-Host "$script:Tag semantic_resource_boundary=$resourceBoundary"
Write-Host "$script:Tag legacy_risky_start_block_present=$riskyStart"
Write-Host "$script:Tag legacy_risky_resource_comment_present=$riskyResource"
Write-Host "$script:Tag legacy_shared_only_guard_present=$riskyGuard"
Write-Host "$script:Tag burst_default_8=$burst8 burst_default_2=$burst2"
Write-Host "$script:Tag compute_resource_calls=$resourceCalls compute_flush_calls=$flushes"
Write-Host "$script:Tag queue_inflight_split_preserved=$($p.Contains('SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT'))"
Write-Host "$script:Tag dcc_v80_present=$($p.Contains('DCC_PROVENANCE_RECOVERY'))"
Write-Host "$script:Tag rigid_sha_gate=False"
if($resourceCalls -ne 1){throw "$script:Tag expected exactly one CreateComputeDispatchResources(work); found $resourceCalls."}
if($already){Write-Host "$script:Tag State=AlreadyApplied"}else{Write-Host "$script:Tag State=Ready"}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
