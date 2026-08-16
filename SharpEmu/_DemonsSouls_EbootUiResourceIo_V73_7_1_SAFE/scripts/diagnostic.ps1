param(
    [string]$RepositoryRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$kernel = Join-Path $root 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$kernelText = [IO.File]::ReadAllText($kernel)
if (-not (Test-ContainsOrdinal -Text $kernelText -Pattern 'SHARPEMU_DEMONSSOULS_UI_READ_SERIALIZATION_V73_7_1')) {
    throw '[V73.7.1] Diagnostic refused: read serialization is not installed.'
}

if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw ('[V73.7.1] EBOOT missing: {0}' -f $Eboot)
}

# Correct SHA-256 of the uploaded/main Demon's Souls EBOOT.
$expectedEboot = '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actualEboot = (Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if ($actualEboot -ne $expectedEboot) {
    throw ('[V73.7.1] Wrong EBOOT for this audit. expected={0} actual={1}' -f $expectedEboot,$actualEboot)
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
    throw '[V73.7.1] SharpEmu.exe not found. Run APPLY/BUILD first.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_7_1_EBOOT_UI_RESOURCE_IO_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout = Join-Path $out 'demons_stdout.log'
$stderr = Join-Path $out 'demons_stderr.log'

$vars = @(
    'SHARPEMU_LOG_IO',
    'SHARPEMU_LOG_IO_FILTER',
    'SHARPEMU_LOG_AMPR_READS',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_DRAWS',
    'SHARPEMU_TRACE_FRAME_PACKETS',
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_SCANOUT_RECOVERY'
)

$old = @{}
foreach ($v in $vars) {
    $old[$v] = [Environment]::GetEnvironmentVariable($v,'Process')
}

try {
    $env:SHARPEMU_LOG_IO = '1'
    $env:SHARPEMU_LOG_IO_FILTER = 'scripts'
    $env:SHARPEMU_LOG_AMPR_READS = '1'
    $env:SHARPEMU_SCANOUT_RECOVERY = 'off'

    foreach ($v in @(
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_RESOURCES',
        'SHARPEMU_TRACE_DRAWS',
        'SHARPEMU_TRACE_FRAME_PACKETS',
        'SHARPEMU_TRACE_LABEL_PROVENANCE'
    )) {
        Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
    }

    Write-Host '[V73.7.1] Starting focused EBOOT UI/resource IO run.'
    Write-Host '[V73.7.1] Let the boot movies finish and keep the post-video state running 20-30 seconds, then close the emulator.'
    Write-Host '[V73.7.1] AMPR source was not modified; relevant paths are filtered after log capture.'

    $p = Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $p.WaitForExit()
    $p.WaitForExit()
    try { $exitCode = $p.ExitCode } catch { $exitCode = 'unavailable' }
}
finally {
    foreach ($v in $vars) {
        if ($null -eq $old[$v]) {
            Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')
        }
    }
}

$outLines = @()
$errLines = @()
if (Test-Path -LiteralPath $stdout -PathType Leaf) {
    $outLines = @([IO.File]::ReadAllLines($stdout))
}
if (Test-Path -LiteralPath $stderr -PathType Leaf) {
    $errLines = @([IO.File]::ReadAllLines($stderr))
}

function Pick-Err([string]$needle) {
    $r = New-Object System.Collections.Generic.List[string]
    foreach ($line in $errLines) {
        if ($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $r.Add($line)
        }
    }
    return $r.ToArray()
}

function Pick-Out([string]$needle) {
    $r = New-Object System.Collections.Generic.List[string]
    foreach ($line in $outLines) {
        if ($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $r.Add($line)
        }
    }
    return $r.ToArray()
}

$amprAll = @(Pick-Err 'ampr.read_file:')
$ampr = @(
    $amprAll |
        Where-Object {
            $_.IndexOf('scripts',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('workspaces',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('coredata',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('misc',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('ui',[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
)

$kernelIo = @(
    $errLines |
        Where-Object {
            $_.IndexOf('[LOADER][TRACE]',[StringComparison]::Ordinal) -ge 0 -and
            $_.IndexOf("path='",[StringComparison]::Ordinal) -ge 0 -and
            $_.IndexOf('scripts',[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
)

$amprFailures = @(
    $ampr |
        Where-Object { $_ -notmatch 'result=0x00000000' }
)

$ioFailures = @(
    $kernelIo |
        Where-Object {
            $_.IndexOf('result=not_found',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('result=io_error',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('result=disposed',[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
)

$readFailures = @(
    $errLines |
        Where-Object {
            $_.IndexOf('result=disposed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('result=io_error',[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
)

$milestones = @()
foreach ($needle in @(
    'Resource dependency file loaded:',
    'ResourcePool::RecordResourceDependencies()',
    'Starting Script:',
    'Starting main loop:',
    'ResourcePool::GatherResourceFileInfo()'
)) {
    $milestones += @(Pick-Out $needle)
}

$uiMarkers = @(
    $errLines |
        Where-Object {
            $_.IndexOf('StartMenu',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('UIManager',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('UITransition',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('presented guest frame',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IndexOf('[V16][CP4_FLIP]',[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
)

$unresolved = @(Pick-Err 'unresolved:')
$deviceLost = @(Pick-Err 'deviceLost=True')

$classification = 'resource-io-clean-ui-blocker-downstream'
if ($amprFailures.Count -gt 0 -or $ioFailures.Count -gt 0 -or $readFailures.Count -gt 0) {
    $classification = 'resource-io-failure-observed'
}
elseif ($milestones.Count -lt 4) {
    $classification = 'resource-init-milestone-missing'
}
elseif ($uiMarkers.Count -gt 0) {
    $classification = 'resource-io-clean-ui-render-path-reached'
}

Write-Utf8Lines -Path (Join-Path $out 'AMPR_UI_READS.txt') -Lines $ampr
Write-Utf8Lines -Path (Join-Path $out 'KERNEL_SCRIPT_IO.txt') -Lines $kernelIo
Write-Utf8Lines -Path (Join-Path $out 'RESOURCE_IO_FAILURES.txt') -Lines @($amprFailures+$ioFailures+$readFailures)
Write-Utf8Lines -Path (Join-Path $out 'RESOURCE_MILESTONES.txt') -Lines $milestones
Write-Utf8Lines -Path (Join-Path $out 'UI_RUNTIME_MARKERS.txt') -Lines $uiMarkers

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.7.1')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actualEboot))
$summary.Add(('ampr_all_reads={0}' -f $amprAll.Count))
$summary.Add(('ampr_ui_reads={0}' -f $ampr.Count))
$summary.Add(('ampr_failures={0}' -f $amprFailures.Count))
$summary.Add(('kernel_script_io={0}' -f $kernelIo.Count))
$summary.Add(('kernel_script_failures={0}' -f $ioFailures.Count))
$summary.Add(('read_disposed_or_io_errors={0}' -f $readFailures.Count))
$summary.Add(('resource_milestones={0}' -f $milestones.Count))
$summary.Add(('ui_runtime_markers={0}' -f $uiMarkers.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

$pkg = Get-PackageRoot
foreach ($name in @(
    'EBOOT_UI_IO_API_MATRIX.csv',
    'EBOOT_READ_ABI_PROOF.txt',
    'EBOOT_UI_RESOURCE_REFERENCES.csv'
)) {
    Copy-Item -LiteralPath (Join-Path $pkg ('evidence\' + $name)) -Destination $out -Force
}

$sourceDir = Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
foreach ($relative in @(
    'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs',
    'src\SharpEmu.Libs\Ampr\AmprExports.cs',
    'src\SharpEmu.Libs\Ampr\AmprFileRegistry.cs'
)) {
    $source = Join-Path $root $relative
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $dest = Join-Path $sourceDir $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
}

$zip = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host ('[V73.7.1] RESULT: {0}' -f $zip)
Write-Host ('[V73.7.1] classification={0}' -f $classification)
Write-Host ('[V73.7.1] AMPR relevant/failures={0}/{1}; kernel script IO/failures={2}/{3}; read IO errors={4}; milestones={5}; UI markers={6}' -f
    $ampr.Count,$amprFailures.Count,$kernelIo.Count,$ioFailures.Count,$readFailures.Count,$milestones.Count,$uiMarkers.Count)
