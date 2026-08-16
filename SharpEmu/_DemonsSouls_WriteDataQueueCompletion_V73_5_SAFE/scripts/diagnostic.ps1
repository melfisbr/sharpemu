param(
    [string]$RepositoryRoot,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
if (-not (Test-ContainsOrdinal `
        -Text ([IO.File]::ReadAllText($agc)) `
        -Pattern 'requiresGpuBufferReadback: false')) {
    throw '[V73.5] Diagnostic refused: V73.5 fix is not installed.'
}

if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw ('[V73.5] EBOOT missing: {0}' -f $Eboot)
}

$exe = $null
foreach ($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $exe = $candidate
        break
    }
}
if ($null -eq $exe) {
    throw '[V73.5] SharpEmu.exe not found. Run RUN_APPLY_BUILD_V73_5.cmd first.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_5_WRITEDATA_PRODUCER_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$stdout = Join-Path $out 'demons_stdout.log'
$stderr = Join-Path $out 'demons_stderr.log'

$variableNames = @(
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_DRAWS',
    'SHARPEMU_TRACE_FRAME_PACKETS',
    'SHARPEMU_TRACE_GEOMETRY_DRAWS'
)
$oldValues = @{}
foreach ($name in $variableNames) {
    $oldValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $env:SHARPEMU_TRACE_LABEL_PROVENANCE = '1'

    foreach ($name in $variableNames) {
        if ($name -ne 'SHARPEMU_TRACE_LABEL_PROVENANCE') {
            Remove-Item ('Env:' + $name) -ErrorAction SilentlyContinue
        }
    }

    Write-Host '[V73.5] Starting representative Demons Souls run.'
    Write-Host '[V73.5] Leave the normal post-video state running long enough for the WRITE_DATA producers to execute, then close the emulator.'
    Write-Host '[V73.5] Only bounded label provenance is enabled.'

    $process = Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $process.WaitForExit()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
}
finally {
    foreach ($name in $variableNames) {
        if ($null -eq $oldValues[$name]) {
            Remove-Item ('Env:' + $name) -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable(
                $name,
                [string]$oldValues[$name],
                'Process')
        }
    }
}

$stdoutLines = @()
$stderrLines = @()

if (Test-Path -LiteralPath $stdout -PathType Leaf) {
    $stdoutLines = @([IO.File]::ReadAllLines($stdout))
}
if (Test-Path -LiteralPath $stderr -PathType Leaf) {
    $stderrLines = @([IO.File]::ReadAllLines($stderr))
}

function Select-DiagnosticLines {
    param([string]$Needle)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $stderrLines) {
        if ($line.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $result.Add($line)
        }
    }
    return $result.ToArray()
}

$targets = @(Select-DiagnosticLines 'wait_target ')
$packets = @(Select-DiagnosticLines 'write_data_packet')
$applied = @(Select-DiagnosticLines 'write_data_applied ')
$resumed = @(Select-DiagnosticLines 'wait_resumed ')
$suspended = @(Select-DiagnosticLines 'agc.wait_suspended')
$fences = @(Select-DiagnosticLines 'vk.ordered_action_fence_wait')
$backpressure = @(Select-DiagnosticLines 'vk.guest_queue_backpressure')
$unresolved = @(Select-DiagnosticLines 'unresolved:')
$deviceLost = @(Select-DiagnosticLines 'deviceLost=True')

$metadata = New-Object System.Collections.Generic.List[string]
foreach ($line in $stdoutLines) {
    if ($line.IndexOf(
            'SCE import metadata:',
            [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $metadata.Add($line)
    }
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.5')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('wait_targets={0}' -f $targets.Count))
$summary.Add(('write_data_packet_lines={0}' -f $packets.Count))
$summary.Add(('write_data_applied={0}' -f $applied.Count))
$summary.Add(('wait_resumed={0}' -f $resumed.Count))
$summary.Add(('wait_suspended={0}' -f $suspended.Count))
$summary.Add(('ordered_fence_sample_lines={0}' -f $fences.Count))
$summary.Add(('backpressure_sample_lines={0}' -f $backpressure.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
foreach ($line in $metadata) {
    $summary.Add(('metadata={0}' -f $line))
}

Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary
Write-Utf8Lines -Path (Join-Path $out 'WRITEDATA_PACKETS.txt') -Lines $packets
Write-Utf8Lines -Path (Join-Path $out 'WRITEDATA_APPLIED.txt') -Lines $applied
Write-Utf8Lines -Path (Join-Path $out 'WAIT_RESUMED.txt') -Lines $resumed
Write-Utf8Lines -Path (Join-Path $out 'WAIT_SUSPENDED.txt') -Lines $suspended
Write-Utf8Lines -Path (Join-Path $out 'ORDERED_FENCE_WAITS.txt') -Lines $fences
Write-Utf8Lines -Path (Join-Path $out 'BACKPRESSURE.txt') -Lines $backpressure

$sourceDir = Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
foreach ($relative in @(
    'src\SharpEmu.Libs\Agc\AgcExports.cs',
    'src\SharpEmu.Libs\Gpu\IGuestGpuBackend.cs',
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
)) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        continue
    }

    $destination = Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) |
        Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$zipPath = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath -Force

Write-Host ('[V73.5] RESULT: {0}' -f $zipPath)
Write-Host (
    '[V73.5] write_data applied={0}; waits resumed={1}; suspended registrations={2}; backpressure samples={3}' -f
    $applied.Count,
    $resumed.Count,
    $suspended.Count,
    $backpressure.Count)
