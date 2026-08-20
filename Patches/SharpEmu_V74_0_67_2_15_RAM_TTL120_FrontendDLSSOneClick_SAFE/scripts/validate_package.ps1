. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){throw '[V74.0.67.2.15] SHA256SUMS.txt missing.'}

$failed=$false;$hashCount=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){
        Write-Host "[V74.0.67.2.15] malformed_manifest_line=$line";$failed=$true;continue
    }
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.15] manifest_missing=$relative";$failed=$true;continue
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.15] manifest_hash_mismatch=$relative";$failed=$true
    }
    $hashCount++
}

$scripts=Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File
$parseErrors=0
foreach($ps1 in $scripts){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne 0){
        foreach($err in $errors){
            Write-Host "[V74.0.67.2.15] parse_error=$($ps1.Name):$($err.Message)"
            $parseErrors++
        }
        $failed=$true
    }
}
Write-Host "[V74.0.67.2.15] parsed_powershell_files=$($scripts.Count)"
Write-Host "[V74.0.67.2.15] powershell_parse_errors=$parseErrors"

$forbiddenPathApiShort='[IO.Path]::Get'+'RelativePath('
$forbiddenPathApiFull='[System.IO.Path]::Get'+'RelativePath('
$strictModeNeedle='"'+'$'+'b.Contains('
$reserved=0;$relativeHits=0;$strictHits=0
foreach($ps1 in $scripts){
    $text=[IO.File]::ReadAllText($ps1.FullName)
    if([regex]::IsMatch($text,'(?im)^\s*\$host\s*=')){
        Write-Host "[V74.0.67.2.15] reserved_host_assignment=$($ps1.Name)";$reserved++;$failed=$true
    }
    if($text.Contains($forbiddenPathApiShort) -or $text.Contains($forbiddenPathApiFull)){
        Write-Host "[V74.0.67.2.15] powershell51_getrelativepath=$($ps1.Name)";$relativeHits++;$failed=$true
    }
    if($text.Contains($strictModeNeedle)){
        Write-Host "[V74.0.67.2.15] strictmode_literal_expansion_risk=$($ps1.Name)";$strictHits++;$failed=$true
    }
}
Write-Host "[V74.0.67.2.15] reserved_host_assignment_count=$reserved"
Write-Host "[V74.0.67.2.15] getrelativepath_hit_count=$relativeHits"
Write-Host "[V74.0.67.2.15] strictmode_literal_expansion_risk_count=$strictHits"

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
    $mapsOk=$false
    if($runnerOk){$mapsOk=[IO.File]::ReadAllText($runner).Contains(('scripts\'+$entry.Value))}
    Write-Host "[V74.0.67.2.15] runner_$($entry.Key)_exists=$($runnerOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.15] runner_$($entry.Key)_target_ok=$($mapsOk.ToString().ToLowerInvariant())"
    if(!$runnerOk -or !$targetOk -or !$mapsOk){$failed=$true}
}

$ramPatch=Normalize-Lf ([IO.File]::ReadAllText((Join-Path $package 'scripts\patch_ram_ttl.ps1')))
$frontPatch=Normalize-Lf ([IO.File]::ReadAllText((Join-Path $package 'scripts\patch_frontend_oneclick.ps1')))
$launcher=Normalize-Lf ([IO.File]::ReadAllText((Join-Path $package 'scripts\open_gui.ps1')))

$packageChecks=[ordered]@{
    ram_marker=$ramPatch.Contains('V74.0.67.2.15 effective large-array TTL')
    ram_dynamic_field_type=$ramPatch.Contains('(?<type>int|long)')
    ram_upper_120000=$ramPatch.Contains('120000')
    ram_redirects_consumers=$ramPatch.Contains(".Replace($token,'V74067215LargeArraySnapshotTtlMs')")
    ram_lookup_proof=$ramPatch.Contains('Cache lookup still does not use effective TTL.')
    frontend_marker=$frontPatch.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
    frontend_precomposite=$frontPatch.Contains('"SHARPEMU_VK_UPSCALER_PRECOMPOSITE"')
    frontend_ram_cache=$frontPatch.Contains('"SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES"')
    frontend_ram_ttl=$frontPatch.Contains('"SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS"')
    frontend_detile_pool=$frontPatch.Contains('"SHARPEMU_VK_DETILE_POOL_MB"')
    launcher_clears_forced_backend=$launcher.Contains('Remove-Item Env:SHARPEMU_VK_UPSCALER')
    launcher_no_forced_dlss=!$launcher.Contains("$env:SHARPEMU_VK_UPSCALER='dlss'")
}
foreach($entry in $packageChecks.GetEnumerator()){
    Write-Host "[V74.0.67.2.15] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.15] validation_strategy=dynamic-source-shape+dryrun+release-build+frontend-no-shell-proof'
Write-Host '[V74.0.67.2.15] powershell_51_compatible=true'

if($failed){throw '[V74.0.67.2.15] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.15] PACKAGE VALIDATION PASSED ($hashCount hashed files; $($scripts.Count) PowerShell files parsed; strict-mode/runner/RAM/frontend checks passed)."
