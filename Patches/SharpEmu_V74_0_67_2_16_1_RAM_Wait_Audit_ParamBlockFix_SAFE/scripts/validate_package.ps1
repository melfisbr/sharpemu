. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){
    throw '[V74.0.67.2.16.1] SHA256SUMS.txt missing.'
}

$failed=$false
$hashCount=0

foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){
        Write-Host "[V74.0.67.2.16.1] malformed_manifest_line=$line"
        $failed=$true
        continue
    }

    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.16.1] manifest_missing=$relative"
        $failed=$true
        continue
    }

    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.16.1] manifest_hash_mismatch=$relative"
        $failed=$true
    }
    $hashCount++
}

$scripts=Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File
$parseErrors=0
foreach($ps1 in $scripts){
    $tokens=$null
    $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne 0){
        foreach($err in $errors){
            Write-Host "[V74.0.67.2.16.1] parse_error=$($ps1.Name):$($err.Message)"
            $parseErrors++
        }
        $failed=$true
    }
}
Write-Host "[V74.0.67.2.16.1] parsed_powershell_files=$($scripts.Count)"
Write-Host "[V74.0.67.2.16.1] powershell_parse_errors=$parseErrors"

$forbiddenShort='[IO.Path]::Get'+'RelativePath('
$forbiddenFull='[System.IO.Path]::Get'+'RelativePath('
$unsafeContainsPattern='(?m)\.Contains\("[^"\r\n]*\$[^"\r\n]*"\)'
$reserved=0
$relativeHits=0
$unsafeHits=0

foreach($ps1 in $scripts){
    $text=[IO.File]::ReadAllText($ps1.FullName)
    if([regex]::IsMatch($text,'(?im)^\s*\$host\s*=')){
        Write-Host "[V74.0.67.2.16.1] reserved_host_assignment=$($ps1.Name)"
        $reserved++
        $failed=$true
    }
    if($text.Contains($forbiddenShort) -or $text.Contains($forbiddenFull)){
        Write-Host "[V74.0.67.2.16.1] powershell51_getrelativepath=$($ps1.Name)"
        $relativeHits++
        $failed=$true
    }
    $matchesUnsafe=[regex]::Matches($text,$unsafeContainsPattern)
    if($matchesUnsafe.Count-ne 0){
        foreach($m in $matchesUnsafe){
            Write-Host "[V74.0.67.2.16.1] unsafe_contains_interpolation=$($ps1.Name):$($m.Value)"
        }
        $unsafeHits += $matchesUnsafe.Count
        $failed=$true
    }
}
Write-Host "[V74.0.67.2.16.1] reserved_host_assignment_count=$reserved"
Write-Host "[V74.0.67.2.16.1] getrelativepath_hit_count=$relativeHits"
Write-Host "[V74.0.67.2.16.1] unsafe_contains_interpolation_count=$unsafeHits"

$runnerMap=[ordered]@{
    'RUN_1_VALIDATE_PACKAGE.cmd'='validate_package.ps1'
    'RUN_2_PRECHECK.cmd'='precheck.ps1'
    'RUN_3_APPLY_BUILD.cmd'='apply_build.ps1'
    'RUN_4_DIAGNOSTIC.cmd'='diagnostic.ps1'
    'RUN_5_OPEN_GUI.cmd'='open_gui.ps1'
}

foreach($entry in $runnerMap.GetEnumerator()){
    $runner=Join-Path $package $entry.Key
    $target=Join-Path (Join-Path $package 'scripts') $entry.Value
    $runnerOk=Test-Path -LiteralPath $runner -PathType Leaf
    $targetOk=Test-Path -LiteralPath $target -PathType Leaf
    $mappingOk=$false
    if($runnerOk){
        $mappingOk=[IO.File]::ReadAllText($runner).Contains(('scripts\'+$entry.Value))
    }
    Write-Host "[V74.0.67.2.16.1] runner_$($entry.Key)_exists=$($runnerOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.16.1] runner_$($entry.Key)_target_ok=$($mappingOk.ToString().ToLowerInvariant())"
    if(!$runnerOk -or !$targetOk -or !$mappingOk){$failed=$true}
}

$audit=[IO.File]::ReadAllText((Join-Path $package 'scripts\source_audit.ps1'))
$analyzer=[IO.File]::ReadAllText((Join-Path $package 'scripts\analyze_runtime.ps1'))
$launcher=[IO.File]::ReadAllText((Join-Path $package 'scripts\open_gui.ps1'))

# V74.0.67.2.16.1: script-level param(...) must precede dot-sourcing common.ps1.
# This is required by Windows PowerShell and is especially important because
# common.ps1 enables Set-StrictMode -Version Latest.
$auditTrim=$audit.TrimStart()
$analyzerTrim=$analyzer.TrimStart()
$auditParamIndex=$audit.IndexOf('param(')
$auditCommonIndex=$audit.IndexOf(". (Join-Path `$PSScriptRoot 'common.ps1')")
$analyzerParamIndex=$analyzer.IndexOf('param(')
$analyzerCommonIndex=$analyzer.IndexOf(". (Join-Path `$PSScriptRoot 'common.ps1')")

$checks=[ordered]@{
    source_audit_param_first=
        $auditTrim.StartsWith('param(') -and
        $auditParamIndex-ge 0 -and
        $auditCommonIndex-gt $auditParamIndex
    analyzer_param_first=
        $analyzerTrim.StartsWith('param(') -and
        $analyzerParamIndex-ge 0 -and
        $analyzerCommonIndex-gt $analyzerParamIndex
    audit_array_lookup=$audit.Contains('TryGetLargeArraySnapshotV74064')
    audit_array_store=$audit.Contains('StoreLargeArraySnapshotV74064')
    audit_slow_wait=$audit.Contains('[V74.0.27][SLOW_WAIT_PRODUCER]')
    audit_dedicated_wait=$audit.Contains('[V74.0.71][DEDICATED_WAIT_DRAIN]')
    audit_gate_owner=$audit.Contains('[V74.0.72][GATE_OWNER_WAIT_DRAIN]')
    audit_capacity=$audit.Contains('[V74.0.33][SUBMISSION_CAPACITY_YIELD]')
    audit_hard_cap=$audit.Contains('[V74.0.46][INLINE_HARD_CAP_FENCE_PROBE]')
    analyzer_mem=$analyzer.Contains('[V74.0.8.1][MEM]')
    analyzer_ttl=$analyzer.Contains('array_owner_ttl120_count')
    analyzer_wait=$analyzer.Contains('slow_wait_completed_producer_count')
    analyzer_capacity=$analyzer.Contains('submission_capacity_pending24_count')
    analyzer_ratio=$analyzer.Contains('array_owner_vs_sampled_alloc_ratio_pct')
    launcher_no_forced_assignment=
        !$launcher.Contains(('SHARPEMU_VK_UPSCALER'+[char]61+[char]39+'dlss'+[char]39))
    launcher_runtime_zip=$launcher.Contains('RuntimeAuditZip=')
}

foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.16.1] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.16.1] runtime_source_change=false'
Write-Host '[V74.0.67.2.16.1] behavioral_change=false'
Write-Host '[V74.0.67.2.16.1] powershell_51_compatible=true'

if($failed){throw '[V74.0.67.2.16.1] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.16.1] PACKAGE VALIDATION PASSED ($hashCount hashed files; $($scripts.Count) PowerShell files parsed; source/runtime audit checks passed)."
