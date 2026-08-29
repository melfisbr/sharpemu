param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$t = [IO.File]::ReadAllText($CliPath)

foreach ($m in @(
    '[V76.3.21.2][GLOBAL_SNAPSHOT_BOUNDS]',
    '[V76.3.21.1][MAX_CRITICAL_PATH_MERGE]',
    '[V76.3.21.0][FORWARD_MAX_MERGE]',
    '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
    '[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE]',
    '[V76.3.15.1][BOOT_LANE6_SAFE_MEMCPY]',
    'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE"',
    'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");'
)) {
    if (-not $t.Contains($m)) {
        Fail "baseline V21.2 contract ausente: $m"
    }
}

if (-not $t.Contains('private static bool IsDemonsSoulsLaunch()')) {
    Fail 'anchor IsDemonsSoulsLaunch ausente'
}

Write-Host "[$Tag] PRECHECK PASSED"
Write-Host "[$Tag] cli_sha256=$(HashLower $CliPath)"
Write-Host (
    "[$Tag] diagnosis=guest-feed-stops-before-natural-bink " +
    "recovery=known-V17.1-scheduler-envelope"
)
