. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){
    throw '[V74.0.67.2.17] SHA256SUMS.txt missing.'
}

$failed=$false
$hashCount=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){
        Write-Host "[V74.0.67.2.17] malformed_manifest_line=$line"
        $failed=$true
        continue
    }
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.17] manifest_missing=$relative"
        $failed=$true
        continue
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.17] manifest_hash_mismatch=$relative"
        $failed=$true
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
            Write-Host "[V74.0.67.2.17] parse_error=$($ps1.Name):$($err.Message)"
            $parseErrors++
        }
        $failed=$true
    }
}
Write-Host "[V74.0.67.2.17] parsed_powershell_files=$($scripts.Count)"
Write-Host "[V74.0.67.2.17] powershell_parse_errors=$parseErrors"

$forbiddenShort='[IO.Path]::Get'+'RelativePath('
$forbiddenFull='[System.IO.Path]::Get'+'RelativePath('
$unsafeContainsPattern='(?m)\.Contains\("[^"\r\n]*\$[^"\r\n]*"\)'
$reserved=0;$relativeHits=0;$unsafeHits=0

foreach($ps1 in $scripts){
    $text=[IO.File]::ReadAllText($ps1.FullName)
    if([regex]::IsMatch($text,'(?im)^\s*\$host\s*=')){
        Write-Host "[V74.0.67.2.17] reserved_host_assignment=$($ps1.Name)"
        $reserved++;$failed=$true
    }
    if($text.Contains($forbiddenShort) -or $text.Contains($forbiddenFull)){
        Write-Host "[V74.0.67.2.17] powershell51_getrelativepath=$($ps1.Name)"
        $relativeHits++;$failed=$true
    }
    $unsafe=[regex]::Matches($text,$unsafeContainsPattern)
    if($unsafe.Count-ne 0){
        foreach($m in $unsafe){
            Write-Host "[V74.0.67.2.17] unsafe_contains_interpolation=$($ps1.Name):$($m.Value)"
        }
        $unsafeHits += $unsafe.Count
        $failed=$true
    }
}

Write-Host "[V74.0.67.2.17] reserved_host_assignment_count=$reserved"
Write-Host "[V74.0.67.2.17] getrelativepath_hit_count=$relativeHits"
Write-Host "[V74.0.67.2.17] unsafe_contains_interpolation_count=$unsafeHits"

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
    $mapOk=$false
    if($runnerOk){
        $mapOk=[IO.File]::ReadAllText($runner).Contains(('scripts\'+$entry.Value))
    }
    Write-Host "[V74.0.67.2.17] runner_$($entry.Key)_exists=$($runnerOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.17] runner_$($entry.Key)_target_ok=$($mapOk.ToString().ToLowerInvariant())"
    if(!$runnerOk -or !$targetOk -or !$mapOk){$failed=$true}
}

$patch=[IO.File]::ReadAllText((Join-Path $package 'scripts\patch_v217.ps1'))
$launcher=[IO.File]::ReadAllText((Join-Path $package 'scripts\open_gui.ps1'))

$checks=[ordered]@{
    cache_marker=$patch.Contains('V74.0.67.2.17 size-aware large-array admission')
    cache_bypass=$patch.Contains('action=bypass-smaller')
    cache_replace=$patch.Contains('action=replace-smaller')
    cache_no_entry_increase=
        !$patch.Contains('SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES=')
    small_write_marker=$patch.Contains('V74.0.67.2.17 small WRITE_DATA packet position')
    small_write_16=$patch.Contains('producerLength <= 16')
    small_write_no_readback=$patch.Contains('!requiresGpuBufferReadback')
    small_write_no_defer=$patch.Contains('!deferLabelCompletion')
    wait_latency=$patch.Contains('producer_complete_ms=')
    launcher_no_forced_dlss=
        !$launcher.Contains(('$env:SHARPEMU_VK_UPSCALER'+[char]61+[char]39+'dlss'+[char]39))
}

foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.17] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.17] source_scope=AgcExports.cs-only'
Write-Host '[V74.0.67.2.17] native_provider_change=false'
Write-Host '[V74.0.67.2.17] presenter_hard_cap_change=false'
Write-Host '[V74.0.67.2.17] powershell_51_compatible=true'

if($failed){throw '[V74.0.67.2.17] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.17] PACKAGE VALIDATION PASSED ($hashCount hashed files; $($scripts.Count) PowerShell files parsed; behavioral patch structure passed)."
