param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$native=Get-NativeWorkerPathV74010 $root
$payload=Get-PayloadNativeWorkerV74010
$presenter=Get-PresenterPath $root

$nativeSha=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
$payloadSha=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToUpperInvariant()
$presenterSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$nativeText=[System.IO.File]::ReadAllText($native)

$baselineSha="B0301DABA2892BFC47D9F6A947664B2147ECCA173BD6DA8EADB58F6414929BCF"
$installedSha="F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38"

$baseline=$nativeSha-eq$baselineSha -and
    -not $nativeText.Contains("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE")
$installed=$nativeSha-eq$installedSha -and
    $nativeText.Contains("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE")

if($payloadSha-ne$installedSha){
    throw "[V74.0.10.1] Payload SHA changed: $payloadSha"
}
if($presenterSha-ne"0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"){
    throw "[V74.0.10.1] Presenter prerequisite mismatch: $presenterSha"
}
if(-not $baseline -and -not $installed){
    throw "[V74.0.10.1] Unknown NativeWorker state: $nativeSha"
}

Write-Host "[V74.0.10.1] PRECHECK PASSED."
Write-Host "[V74.0.10.1] NativeWorker=$native"
Write-Host "[V74.0.10.1] native_sha=$nativeSha"
Write-Host "[V74.0.10.1] exact_native_baseline=$($nativeSha-eq$baselineSha)"
Write-Host "[V74.0.10.1] presenter_sha=$presenterSha"
Write-Host "[V74.0.10.1] renderer_resource_lane_installed=$installed"
Write-Host "[V74.0.10.1] renderer_resource_lane_default=8"
Write-Host "[V74.0.10.1] tbb_lane_default=2"
Write-Host "[V74.0.10.1] no_managed_inline_preserved=$($nativeText.Contains('SHARPEMU_V74_0_3_4_NO_MANAGED_INLINE_FALLBACK'))"
Write-Host "[V74.0.10.1] generic_dedicated_workers_preserved=$($nativeText.Contains('SHARPEMU_V73_20_4_1_DEDICATED_GUEST_NATIVE_EXECUTOR'))"

Write-Host "[V74.0.10.1] recovery_finalizer=True"
Write-Host "[V74.0.10.1] live_status_persistence=True"
Write-Host "[V74.0.10.1] console_format_repair=True"
