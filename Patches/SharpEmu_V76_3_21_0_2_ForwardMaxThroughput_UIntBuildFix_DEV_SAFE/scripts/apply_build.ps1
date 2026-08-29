param()
. (Join-Path $PSScriptRoot 'common.ps1')

Ensure-Layout
Assert-SemanticDualQueueContract | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $Patches ("V76_3_21_0_1_PRE_PRESENTER_$stamp.cs")
$summary = Join-Path $Patches ("V76_3_21_0_1_BRIDGE_$stamp.txt")

Copy-Item -LiteralPath $PresenterPath -Destination $backup -Force

$beforeHash = Get-HashLower $PresenterPath
$markerAdded = $false

try {
    $markerAdded = Add-CompatibilityMarker
    $uintBridgeAdded = Add-MaxFramesCommandBufferCountUIntBridge
    $bridgeHash = Get-HashLower $PresenterPath

    Write-Host "[$Tag] presenter_sha_bridge=$bridgeHash"
    Write-Host "[$Tag] running original V21.0 PRECHECK"

    Push-Location $OriginalPkg
    try {
        & (Join-Path $OriginalPkg 'RUN_2_PRECHECK.cmd')
        if ($LASTEXITCODE -ne 0) {
            throw "V21.0 original RUN_2 falhou exit=$LASTEXITCODE"
        }

        Write-Host "[$Tag] original V21.0 PRECHECK PASSED"

        & (Join-Path $OriginalPkg 'RUN_3_APPLY_BUILD.cmd')
        if ($LASTEXITCODE -ne 0) {
            throw "V21.0 original RUN_3 falhou exit=$LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $afterHash = Get-HashLower $PresenterPath

    $afterText = [IO.File]::ReadAllText($PresenterPath)
    if (-not $afterText.Contains(
        'CommandBufferCount = (uint)MaxFramesInFlight,')) {
        throw 'V21 buildfix perdido apos merge: cast uint ausente'
    }
    if (-not $afterText.Contains(
        'SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210')) {
        throw 'V21 merge nao aplicou frames-in-flight configuravel'
    }

    @(
        'tag=V76.3.21.0.2-FORWARD-MAX-THROUGHPUT-UINT-BUILDFIX',
        "presenter_sha_before=$beforeHash",
        "presenter_sha_bridge=$bridgeHash",
        "presenter_sha_after_v21=$afterHash",
        "marker_added=$markerAdded",
        "uint_bridge_added=$uintBridgeAdded",
        "compile_fix=CommandBufferCount=(uint)MaxFramesInFlight",
        'runtime_behavior_added_by_bridge=0',
        'v21_original_improvements_preserved=1',
        'original_v21_precheck=passed',
        'original_v21_apply_build=passed',
        "backup=$backup"
    ) | Set-Content -LiteralPath $summary -Encoding UTF8

    Write-Host (
        "[$Tag] APPLY+BUILD PASSED " +
        "via=original-V21.0 uint_buildfix=1 improvements_preserved=1"
    )
    Write-Host "[$Tag] presenter_sha_after=$afterHash"
    Write-Host "[$Tag] backup=$backup"
    Write-Host "[$Tag] bridge_summary=$summary"
}
catch {
    Copy-Item -LiteralPath $backup -Destination $PresenterPath -Force

    Write-Host (
        "[$Tag] rollback=completed " +
        "presenter_restored_sha=$(Get-HashLower $PresenterPath)"
    ) -ForegroundColor Yellow

    throw
}
