param()
. (Join-Path $PSScriptRoot 'common.ps1')
$state=Join-Path (PatchesRoot) 'SharpEmu_V74_0_117_1_1_SCRIPT_REPAIR_STATE.txt'
if(-not(Test-Path -LiteralPath $state)){throw "$script:Tag RUN_2 repair state missing; run RUN_2 first"}
Parse-PowerShellTree (OriginalRoot)
Invoke-OriginalCmd 'RUN_3_APPLY_BUILD.cmd'
Write-Tag 'ORIGINAL V117.1 APPLY/BUILD PASSED THROUGH REPAIRED CALLER.'
