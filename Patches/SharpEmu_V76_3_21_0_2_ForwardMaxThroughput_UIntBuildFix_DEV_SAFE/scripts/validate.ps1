param()
. (Join-Path $PSScriptRoot 'common.ps1')

Ensure-Layout

# Validate the original package first. This keeps its own package integrity
# authoritative and proves we are not replacing it.
Push-Location $OriginalPkg
try {
    & (Join-Path $OriginalPkg 'RUN_1_VALIDATE_PACKAGE.cmd')
    if ($LASTEXITCODE -ne 0) {
        Fail "V21.0 original RUN_1 falhou exit=$LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Assert-SemanticDualQueueContract | Out-Null

Write-Host (
    "[$Tag] VALIDATE PASSED " +
    "original_v21=preserved source_behavior_change=0 semantic_bridge=ready"
)


$commonText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'common.ps1'))
foreach ($m in @(
    'Add-MaxFramesCommandBufferCountUIntBridge',
    'CommandBufferCount = (uint)MaxFramesInFlight,',
    'compile_fix=CommandBufferCount-int-to-uint'
)) {
    if (-not $commonText.Contains($m)) {
        Fail "buildfix contract ausente: $m"
    }
}

Write-Host (
    "[$Tag] BUILD FIX VALIDATED " +
    "cause=MaxFramesInFlight-promoted-const-to-readonly-int " +
    "fix=explicit-uint-cast"
)
