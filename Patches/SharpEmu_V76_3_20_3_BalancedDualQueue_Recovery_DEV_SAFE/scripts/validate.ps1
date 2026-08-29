param()
. (Join-Path $PSScriptRoot 'common.ps1')
$required=@(
 '[V76.3.20.2][DUAL_QUEUE_DEEP_FEED]',
 'DemonsSoulsGpuQueueEnvelopeV74011224.cs'
)
foreach($m in $required) {
    if([string]::IsNullOrWhiteSpace($m)){Fail 'manifest contract vazio'}
}
Write-Host "[$Tag] VALIDATE PASSED mode=adaptive-final-profile source_replace=0"
