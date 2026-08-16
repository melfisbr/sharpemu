param(
    [string]$RepositoryRoot,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw ('[V73.1] EBOOT missing: {0}' -f $Eboot)
}

$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$source = [IO.File]::ReadAllText($selfLoader)
foreach ($marker in @(
    'DtSceNeededModuleGen5 = 0x61000045',
    'DtSceImportLibGen5 = 0x61000049',
    'DtSceNeededModule || tag == DtSceNeededModuleGen5',
    'case DtSceNeededModuleGen5:',
    'case DtSceImportLibGen5:'
)) {
    if (-not (Test-ContainsOrdinal -Text $source -Pattern $marker)) {
        throw ('[V73.1] Diagnostic refused: integration marker missing: {0}' -f $marker)
    }
}

$candidates = @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)
$exe = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $exe = $candidate
        break
    }
}
if ($null -eq $exe) {
    throw '[V73.1] SharpEmu.exe not found. Run RUN_APPLY_BUILD_V73_1.cmd first.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_1_METADATA_IMPORT_TRACE_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$stdout = Join-Path $out 'demons_stdout.log'
$stderr = Join-Path $out 'demons_stderr.log'
$namedCsv = Join-Path $packageRoot 'evidence\EBOOT_VS_CURRENT_HLE_NAMED.csv'
Copy-Item -LiteralPath $namedCsv -Destination (Join-Path $out 'EBOOT_VS_CURRENT_HLE_NAMED.csv') -Force
Copy-Item -LiteralPath (Join-Path $packageRoot 'evidence\MODULE_HLE_COVERAGE.csv') -Destination (Join-Path $out 'MODULE_HLE_COVERAGE.csv') -Force

$oldAgc = $env:SHARPEMU_LOG_AGC
$oldAgcShader = $env:SHARPEMU_LOG_AGC_SHADER
$oldVk = $env:SHARPEMU_LOG_VK_RESOURCES

try {
    Remove-Item Env:SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_LOG_AGC_SHADER -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_LOG_VK_RESOURCES -ErrorAction SilentlyContinue

    Write-Host '[V73.1] Starting Demons Souls metadata/import trace.'
    Write-Host '[V73.1] Close the emulator after reaching the normal post-video stall/menu transition.'
    Write-Host ('[V73.1] Executable: {0}' -f $exe)

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
    if ($null -eq $oldAgc) { Remove-Item Env:SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_AGC = $oldAgc }
    if ($null -eq $oldAgcShader) { Remove-Item Env:SHARPEMU_LOG_AGC_SHADER -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_AGC_SHADER = $oldAgcShader }
    if ($null -eq $oldVk) { Remove-Item Env:SHARPEMU_LOG_VK_RESOURCES -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_VK_RESOURCES = $oldVk }
}

$allLogPaths = @($stdout, $stderr)
$metadataMatches = @(Select-String -LiteralPath $allLogPaths -Pattern 'SCE import metadata:' -ErrorAction SilentlyContinue)
$metadataText = ''
if ($metadataMatches.Count -gt 0) {
    $metadataText = [string]$metadataMatches[0].Line
}

$libraries = -1
$modules = -1
if ($metadataText -match 'libraries=(\d+)\s+modules=(\d+)') {
    $libraries = [int]$Matches[1]
    $modules = [int]$Matches[2]
}

$staticRows = @(Import-Csv -LiteralPath $namedCsv)
$staticByNid = @{}
foreach ($row in $staticRows) {
    $staticByNid[[string]$row.Nid] = $row
}

$unresolvedCounts = @{}
$unresolvedSamples = @{}
$unresolvedMatches = @(Select-String -LiteralPath $allLogPaths -Pattern 'unresolved:\s+nid=([^\s]+)' -AllMatches -ErrorAction SilentlyContinue)
foreach ($lineMatch in $unresolvedMatches) {
    foreach ($regexMatch in $lineMatch.Matches) {
        $nid = [string]$regexMatch.Groups[1].Value
        if (-not $unresolvedCounts.ContainsKey($nid)) {
            $unresolvedCounts[$nid] = 0
            $unresolvedSamples[$nid] = [string]$lineMatch.Line
        }
        $unresolvedCounts[$nid] = [int]$unresolvedCounts[$nid] + 1
    }
}

$runtimeRows = @()
foreach ($nid in @($unresolvedCounts.Keys | Sort-Object)) {
    $static = $null
    if ($staticByNid.ContainsKey($nid)) {
        $static = $staticByNid[$nid]
    }

    $row = New-Object PSObject
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'Nid' -Value $nid
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'RuntimeUnresolvedCount' -Value ([int]$unresolvedCounts[$nid])
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'Module' -Value $(if ($null -ne $static) { [string]$static.Module } else { '' })
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'Library' -Value $(if ($null -ne $static) { [string]$static.Library } else { '' })
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'Kind' -Value $(if ($null -ne $static) { [string]$static.Kind } else { '' })
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'StaticStatus' -Value $(if ($null -ne $static) { [string]$static.Status } else { 'NOT_IN_EBOOT_STATIC_TABLE' })
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'CatalogName' -Value $(if ($null -ne $static) { [string]$static.CatalogName } else { '' })
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'StaticDisposition' -Value $(if ($null -ne $static) { [string]$static.StaticDisposition } else { '' })
    Add-Member -InputObject $row -MemberType NoteProperty -Name 'Sample' -Value ([string]$unresolvedSamples[$nid])
    $runtimeRows += $row
}

$runtimeRows = @($runtimeRows | Sort-Object -Property @{Expression='RuntimeUnresolvedCount';Descending=$true}, @{Expression='Nid';Descending=$false})
$runtimeRows | Export-Csv -LiteralPath (Join-Path $out 'RUNTIME_UNRESOLVED_IMPORTS.csv') -NoTypeInformation -Encoding UTF8

$summary = @()
$summary += 'version=73.1'
$summary += ('exit_code={0}' -f $exitCode)
$summary += ('metadata_line={0}' -f $metadataText)
$summary += ('metadata_libraries={0}' -f $libraries)
$summary += ('metadata_modules={0}' -f $modules)
$summary += ('expected_demons_libraries=53')
$summary += ('expected_demons_modules=49')
$summary += ('metadata_expected_match={0}' -f (($libraries -eq 53) -and ($modules -eq 49)))
$summary += ('runtime_unresolved_distinct={0}' -f $runtimeRows.Count)
$summary += ('runtime_unresolved_calls={0}' -f (($unresolvedCounts.Values | Measure-Object -Sum).Sum))
$summary += ('selfloader_sha256={0}' -f (Get-FileHash -LiteralPath $selfLoader -Algorithm SHA256).Hash)
$summary | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

$sourceLines = [IO.File]::ReadAllLines($selfLoader)
$sourceEvidence = @()
$patterns = @(
    'DtSceNeededModuleGen5',
    'DtSceImportLibGen5',
    'CollectNeededModuleNames(',
    'ParseSceImportMetadata(',
    'case DtSceNeededModuleGen5:',
    'case DtSceImportLibGen5:'
)
foreach ($pattern in $patterns) {
    for ($i = 0; $i -lt $sourceLines.Length; $i++) {
        if ($sourceLines[$i].IndexOf($pattern, [StringComparison]::Ordinal) -ge 0) {
            $first = [Math]::Max(0, $i - 12)
            $last = [Math]::Min($sourceLines.Length - 1, $i + 24)
            $sourceEvidence += ('===== {0} line={1} =====' -f $pattern, ($i + 1))
            for ($j = $first; $j -le $last; $j++) {
                $sourceEvidence += ('{0,6}: {1}' -f ($j + 1), $sourceLines[$j])
            }
        }
    }
}
$sourceEvidence | Set-Content -LiteralPath (Join-Path $out 'SELFLOADER_V73_1_EVIDENCE.txt') -Encoding UTF8

$zipPath = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath -Force
Write-Host ('[V73.1] RESULT: {0}' -f $zipPath)
Write-Host ('[V73.1] metadata libraries/modules={0}/{1} expected=53/49' -f $libraries, $modules)
Write-Host ('[V73.1] runtime unresolved distinct={0}' -f $runtimeRows.Count)
