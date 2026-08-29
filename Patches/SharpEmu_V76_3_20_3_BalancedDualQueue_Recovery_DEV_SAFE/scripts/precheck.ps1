param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
$cli=[IO.File]::ReadAllText($CliPath)
if(-not$cli.Contains('[V76.3.20.2][DUAL_QUEUE_DEEP_FEED]')) {
    Fail 'baseline marker ausente: [V76.3.20.2][DUAL_QUEUE_DEEP_FEED]'
}
foreach($m in @(
 'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE"',
 'Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC"',
 'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR"',
 'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171"',
 'Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151"'
)) {
 if(-not$cli.Contains($m)){Fail "baseline contract ausente: $m"}
}
Write-Host "[$Tag] PRECHECK PASSED baseline=[V76.3.20.2][DUAL_QUEUE_DEEP_FEED]"
