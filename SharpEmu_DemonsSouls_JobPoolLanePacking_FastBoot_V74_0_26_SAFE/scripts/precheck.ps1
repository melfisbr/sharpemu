param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74026 -RepositoryRoot $RepositoryRoot
$requiredPaths=@(
    (Get-AgcPathV74026 -Root $repoRoot),
    (Get-PresenterPathV74026 -Root $repoRoot),
    (Get-CpuPathV74026 -Root $repoRoot),
    (Get-DirectPathV74026 -Root $repoRoot),
    (Get-KernelPathV74026 -Root $repoRoot),
    (Get-HostMoviePathV74026 -Root $repoRoot)
)
foreach ($requiredPath in $requiredPaths) {
    if (-not [System.IO.File]::Exists($requiredPath)) { throw "[V74.0.26] Required source missing: $requiredPath" }
}
if (-not (Test-V21AbiAppliedV74026 -Root $repoRoot)) { throw "[V74.0.26] V74.0.21 EBOOT Entry ABI rollup is not present." }
if (-not (Test-PresenterRollupV74026 -Root $repoRoot)) { throw "[V74.0.26] V74.0.23.1/V74.0.24 presenter rollup is not present." }
if (-not (Test-V25AppliedV74026 -Root $repoRoot)) { throw "[V74.0.26] V74.0.25 WRITE_DATA packet-position source repair is not present." }
if (-not (Test-HostLaneSupportV74026 -Root $repoRoot)) { throw "[V74.0.26] Host-lane affinity support does not match the expected accumulated source." }

$processorCount=[Environment]::ProcessorCount
if ($processorCount -lt 16) { throw "[V74.0.26] This A/B profile requires at least 16 logical processors; detected $processorCount." }
$defaultReserved=[Math]::Max(2,[int]([Math]::Floor($processorCount*3/8)))
$testReserved=[Math]::Max(0,$processorCount-10)
$testUsable=[Math]::Max($processorCount-$testReserved,2)
$uniqueBpeLanes=New-Object 'System.Collections.Generic.HashSet[int]'
$bpeMap=New-Object 'System.Collections.Generic.List[string]'
for($guestCpu=0;$guestCpu -le 12;$guestCpu++){
    $hostCpu=Get-HostCpuForGuestV74026 -GuestCpu $guestCpu -ProcessorCount $processorCount -ReservedLanes $testReserved
    [void]$uniqueBpeLanes.Add($hostCpu)
    $bpeMap.Add("$guestCpu->$hostCpu")
}

Write-Host "[V74.0.26] PRECHECK PASSED."
Write-Host "[V74.0.26] processor_count=$processorCount default_reserved=$defaultReserved default_usable=$($processorCount-$defaultReserved)"
Write-Host "[V74.0.26] test_reserved=$testReserved test_usable=$testUsable BPE_CPU0_12_unique_host_lanes=$($uniqueBpeLanes.Count)"
Write-Host "[V74.0.26] BPE map: $([string]::Join(', ',@($bpeMap)))"
Write-Host "[V74.0.26] No source will be modified. V74.0.25 WRITE_DATA + V74.0.24 texture fixes are preserved."
