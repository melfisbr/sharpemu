param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")
$root=Resolve-RepoRoot $RepositoryRoot
$host=Get-HostMovieBridgePathV74013 $root
$presenter=Get-PresenterPathV74013 $root
$native=Get-NativeWorkerPathV74013 $root
$state=Test-V74013State -HostMovie $host -Presenter $presenter -Native $native
if(-not $state.V12 -and -not $state.V13){
    throw "[V74.0.13.1] V74.0.12 startup handoff is not installed. Apply V74.0.12 first."
}
if(-not $state.Presenter){throw "[V74.0.13.1] V74.0.12 presenter/runtime-scale support not found."}
if(-not $state.Native){throw "[V74.0.13.1] Native/resource lane support not found."}
Write-Host "[V74.0.13.1] PRECHECK PASSED."
Write-Host "[V74.0.13.1] host_v74012=$($state.V12) host_v74013=$($state.V13)"
Write-Host "[V74.0.13.1] presenter_render_scale=True native_lanes=True"
Write-Host "[V74.0.13.1] target: Release runtime + render_scale=0.5 + bounded Vulkan caches + robust Bink completion handoff."
