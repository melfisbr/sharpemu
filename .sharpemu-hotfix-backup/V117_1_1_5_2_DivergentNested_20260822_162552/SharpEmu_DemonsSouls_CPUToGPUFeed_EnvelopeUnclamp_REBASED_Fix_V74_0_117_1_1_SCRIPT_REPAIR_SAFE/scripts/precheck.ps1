param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'repair_original.ps1')
Invoke-OriginalCmd 'RUN_2_PRECHECK.cmd'
Write-Tag 'REPAIRED V117.1 PRECHECK PASSED.'
