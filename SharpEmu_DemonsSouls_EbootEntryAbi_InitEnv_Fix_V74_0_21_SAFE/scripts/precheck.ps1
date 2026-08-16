param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74021 -RepositoryRoot $RepositoryRoot
$cpuPath=Get-CpuDispatcherPathV74021 -Root $repoRoot
$directPath=Get-DirectBackendPathV74021 -Root $repoRoot
$kernelPath=Get-KernelExportsPathV74021 -Root $repoRoot

$cpuText=[System.IO.File]::ReadAllText($cpuPath)
$directText=[System.IO.File]::ReadAllText($directPath)
$kernelText=[System.IO.File]::ReadAllText($kernelPath)

$cpuState=Get-EntryAbiStateV74021 -Text $cpuText
$directState=Get-LleInitEnvStateV74021 -Text $directText
$kernelState=Get-InitEnvStateV74021 -Text $kernelText

foreach($statePair in @(
    [pscustomobject]@{Name="CpuDispatcher.EntryParams";State=$cpuState},
    [pscustomobject]@{Name="DirectExecutionBackend._init_env";State=$directState},
    [pscustomobject]@{Name="KernelExports.InitEnv";State=$kernelState})){
    if($statePair.State -eq "Unknown"){
        throw "[V74.0.21] Unrecognized source state: $($statePair.Name)=$($statePair.State). No source was modified."
    }
}

$hostPath=Get-HostMovieBridgePathV74021 -Root $repoRoot
$hostHash="missing"
if([System.IO.File]::Exists($hostPath)){$hostHash=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash}

Write-Host "[V74.0.21] PRECHECK PASSED."
Write-Host "[V74.0.21] entry_abi_state=$cpuState"
Write-Host "[V74.0.21] lle_init_env_state=$directState"
Write-Host "[V74.0.21] hle_init_env_state=$kernelState"
Write-Host "[V74.0.21] HostMovieBridge SHA256=$hostHash (audit only; RUN_3 does not modify it)"
Write-Host "[V74.0.21] Target correction: EBOOT EntryParams + gated libc _init_env; native CALL trampoline remains unchanged."
