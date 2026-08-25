param()
. (Join-Path $PSScriptRoot 'common.ps1')
$state=Join-Path (PatchesRoot) 'SharpEmu_V74_0_117_1_1_SCRIPT_REPAIR_STATE.txt'
if(-not(Test-Path -LiteralPath $state)){throw "$script:Tag repair state missing"}
Invoke-OriginalCmd 'RUN_4_TEST_DEMONS_CPU_GPU_FEED.cmd'
