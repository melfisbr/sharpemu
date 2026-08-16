param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74022 -RepositoryRoot $RepositoryRoot
$cpuPath=Get-CpuDispatcherPathV74022 -Root $repoRoot
$directPath=Get-DirectBackendPathV74022 -Root $repoRoot
$kernelPath=Get-KernelExportsPathV74022 -Root $repoRoot
$hostPath=Get-HostMovieBridgePathV74022 -Root $repoRoot

$cpuText=[System.IO.File]::ReadAllText($cpuPath)
$directText=[System.IO.File]::ReadAllText($directPath)
$kernelText=[System.IO.File]::ReadAllText($kernelPath)
$hostText=[System.IO.File]::ReadAllText($hostPath)

$cpuState=Get-EntryAbiStateV74022 -Text $cpuText
$directState=Get-LleInitEnvStateV74022 -Text $directText
$kernelState=Get-InitEnvStateV74022 -Text $kernelText

if($cpuState -ne "Applied"){
    throw "[V74.0.22] V74.0.21 EntryParams correction is not applied: $cpuState. Run V74.0.21 RUN_3 first."
}
if($directState -ne "Applied"){
    throw "[V74.0.22] V74.0.21 gated LLE _init_env correction is not applied: $directState."
}
if($kernelState -ne "Applied"){
    throw "[V74.0.22] V74.0.21 HLE _init_env fallback correction is not applied: $kernelState."
}
foreach($guard in @(
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_STARTUP_COMPLETION_SHIM",
    "bink2.startup_completion_shim"
)){
    if(-not $hostText.Contains($guard)){
        throw "[V74.0.22] Required HostMovieBridge natural-handoff capability missing: $guard"
    }
}

$hostHash=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.22] PRECHECK PASSED."
Write-Host "[V74.0.22] EntryParams=Applied; LLE _init_env=Applied; HLE fallback=Applied."
Write-Host "[V74.0.22] HostMovieBridge SHA256=$hostHash (audit only; this package does not modify it)."
Write-Host "[V74.0.22] V74.0.21 result proved the previous close was runner-forced after ABI proof, not a guest crash."
Write-Host "[V74.0.22] Target: guest-owned boot, host auto-boot OFF, natural Bink completion shim ON, no automatic process kill."
