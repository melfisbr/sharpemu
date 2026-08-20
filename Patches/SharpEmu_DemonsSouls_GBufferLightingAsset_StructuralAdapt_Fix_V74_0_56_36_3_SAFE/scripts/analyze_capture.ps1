param(
    [Parameter(Mandatory=$true)][string]$CaptureDirectory,
    [double]$WallSeconds = 0,
    [string]$ExitCode = 'unknown'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stderrPath = Join-Path $CaptureDirectory 'stderr.log'

$stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    [IO.File]::ReadAllText($stderrPath)
}
else {
    ''
}

function Hits([string]$Pattern) {
    return ([regex]::Matches(
        $stderr,
        $Pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )).Count
}

function MaxCounter([string]$Pattern) {
    $maximum = 0L

    foreach ($match in [regex]::Matches(
        $stderr,
        $Pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )) {
        $value = 0L

        if ([long]::TryParse($match.Groups[1].Value, [ref]$value) -and
            $value -gt $maximum) {
            $maximum = $value
        }
    }

    return $maximum
}

$fps = @()

foreach ($match in [regex]::Matches(
    $stderr,
    '\[PERF\]\[RENDER\].*?fps=([0-9]+(?:[,.][0-9]+)?)'
)) {
    $value = 0.0

    if ([double]::TryParse(
        $match.Groups[1].Value.Replace(',', '.'),
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$value
    )) {
        $fps += $value
    }
}

$timelineCompleted = 0L
$timelineSubmitted = 0L

foreach ($match in [regex]::Matches(
    $stderr,
    'timeline=([0-9]+)/([0-9]+)'
)) {
    $completed = 0L
    $submitted = 0L

    [void][long]::TryParse($match.Groups[1].Value, [ref]$completed)
    [void][long]::TryParse($match.Groups[2].Value, [ref]$submitted)

    if ($submitted -gt $timelineSubmitted) {
        $timelineCompleted = $completed
        $timelineSubmitted = $submitted
    }
}

$lastFps = 0
$peakFps = 0

if ($fps.Count -gt 0) {
    $lastFps = [Math]::Round($fps[-1], 2)
    $peakFps = [Math]::Round(($fps | Measure-Object -Maximum).Maximum, 2)
}

@(
    'SharpEmu V74.0.56.36.3 GBUFFER/LIGHTING STRUCTURAL-ADAPT RESULT',
    ('wall_seconds={0}' -f [Math]::Round($WallSeconds, 3)),
    ('exit_code={0}' -f $ExitCode),
    ('gbuffer_contract_counter={0}' -f (MaxCounter '\[V74\.0\.56\.36\]\[GBUFFER_LIGHTING\].*?count=([0-9]+)')),
    ('gbuffer_slot1_added_hits={0}' -f (Hits '\[V74\.0\.56\.36\]\[GBUFFER_LIGHTING\].*?action=added-slot1')),
    ('gbuffer_slot1_present_hits={0}' -f (Hits '\[V74\.0\.56\.36\]\[GBUFFER_LIGHTING\].*?action=slot1-present')),
    ('gbuffer_metadata_repair_hits={0}' -f (Hits '\[V74\.0\.56\.36\]\[GBUFFER_LIGHTING\].*?metadata_repaired=1')),
    ('dcc_fastclear_materialize_counter={0}' -f (MaxCounter '\[V74\.0\.56\.35\]\[DCC_FASTCLEAR\].*?action=materialize.*?count=([0-9]+)')),
    ('dcc_fastclear_45d55_hits={0}' -f (Hits '\[V74\.0\.56\.35\]\[DCC_FASTCLEAR\].*?action=target.*?addr=0x000000045D550000\b')),
    ('dcc_deferred_46089_hits={0}' -f (Hits '\[V74\.0\.56\.32\]\[DCC_DEFER\].*?addr=0x0000000460890000\b')),
    ('dcc_metadata_alias_hit_counter={0}' -f (MaxCounter '\[V74\.0\.56\.32\]\[DCC_META_ALIAS\].*?action=hit count=([0-9]+)')),
    ('dcc_metadata_alias_46089_hits={0}' -f (Hits '\[V74\.0\.56\.32\]\[DCC_META_ALIAS\].*?action=hit.*?(?:sample|image)=0x0000000460890000\b')),
    ('dcc_metadata_alias_miss_counter={0}' -f (MaxCounter '\[V74\.0\.56\.32\]\[DCC_META_ALIAS\].*?action=miss count=([0-9]+)')),
    ('dedicated_wait_drain_logs={0}' -f (Hits '\[V74\.0\.71\]\[DEDICATED_WAIT_DRAIN\]')),
    ('gate_owner_wait_drain_logs={0}' -f (Hits '\[V74\.0\.72\]\[GATE_OWNER_WAIT_DRAIN\]')),
    ('native_exception_hits={0}' -f (Hits 'NATIVE EXCEPTION CAUGHT!')),
    ('device_lost_hits={0}' -f (Hits 'ErrorDeviceLost|deviceLost=True|device lost')),
    ('timeline_completed={0}' -f $timelineCompleted),
    ('timeline_submitted={0}' -f $timelineSubmitted),
    ('render_fps_last={0}' -f $lastFps),
    ('render_fps_peak={0}' -f $peakFps)
) | Set-Content `
    -LiteralPath (Join-Path $CaptureDirectory 'SUMMARY.txt') `
    -Encoding UTF8
