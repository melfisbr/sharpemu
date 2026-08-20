. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){
    throw '[V74.0.67.2.20] SHA256SUMS.txt missing.'
}

$failed=$false
$hashCount=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){
        Write-Host "[V74.0.67.2.20] malformed_manifest_line=$line"
        $failed=$true
        continue
    }
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.20] manifest_missing=$relative"
        $failed=$true
        continue
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.20] manifest_hash_mismatch=$relative"
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
            Write-Host "[V74.0.67.2.20] parse_error=$($ps1.Name):$($err.Message)"
            $parseErrors++
        }
        $failed=$true
    }
}

Write-Host "[V74.0.67.2.20] parsed_powershell_files=$($scripts.Count)"
Write-Host "[V74.0.67.2.20] powershell_parse_errors=$parseErrors"

$forbiddenShort='[IO.Path]::Get'+'RelativePath('
$forbiddenFull='[System.IO.Path]::Get'+'RelativePath('
$unsafeContainsPattern='(?m)\.Contains\("[^"\r\n]*\$[^"\r\n]*"\)'
$reserved=0;$relativeHits=0;$unsafeHits=0

foreach($ps1 in $scripts){
    $text=[IO.File]::ReadAllText($ps1.FullName)
    if([regex]::IsMatch($text,'(?im)^\s*\$host\s*=')){
        Write-Host "[V74.0.67.2.20] reserved_host_assignment=$($ps1.Name)"
        $reserved++;$failed=$true
    }
    if($text.Contains($forbiddenShort) -or $text.Contains($forbiddenFull)){
        Write-Host "[V74.0.67.2.20] powershell51_getrelativepath=$($ps1.Name)"
        $relativeHits++;$failed=$true
    }
    $unsafe=[regex]::Matches($text,$unsafeContainsPattern)
    if($unsafe.Count-ne 0){
        foreach($m in $unsafe){
            Write-Host "[V74.0.67.2.20] unsafe_contains_interpolation=$($ps1.Name):$($m.Value)"
        }
        $unsafeHits += $unsafe.Count
        $failed=$true
    }
}

Write-Host "[V74.0.67.2.20] reserved_host_assignment_count=$reserved"
Write-Host "[V74.0.67.2.20] getrelativepath_hit_count=$relativeHits"
Write-Host "[V74.0.67.2.20] unsafe_contains_interpolation_count=$unsafeHits"

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
    Write-Host "[V74.0.67.2.20] runner_$($entry.Key)_exists=$($runnerOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.20] runner_$($entry.Key)_target_ok=$($mapOk.ToString().ToLowerInvariant())"
    if(!$runnerOk -or !$targetOk -or !$mapOk){$failed=$true}
}

$deploy=[IO.File]::ReadAllText((Join-Path $package 'scripts\patch_dualconfig_deployment.ps1'))
$apply=[IO.File]::ReadAllText((Join-Path $package 'scripts\apply_build.ps1'))
$launcher=[IO.File]::ReadAllText((Join-Path $package 'scripts\open_gui.ps1'))

$checks=[ordered]@{
    deploy_marker=$deploy.Contains('V74.0.67.2.20 DLSS dual-config runtime deployment')
    deploy_canonical_runtime=$deploy.Contains('runtime\dlss')
    deploy_provider_link=$deploy.Contains('Link="upscalers\SharpEmu.VulkanUpscaler.Native.dll"')
    deploy_ngx_link=$deploy.Contains('Link="nvngx_dlss.dll"')
    deploy_output_copy=$deploy.Contains('CopyToOutputDirectory="PreserveNewest"')
    deploy_publish_copy=$deploy.Contains('CopyToPublishDirectory="PreserveNewest"')
    apply_release_build=$apply.Contains("-Configuration 'Release'")
    apply_debug_build=$apply.Contains("-Configuration 'Debug'")
    apply_hash_check=$apply.Contains('provider hash differs from canonical runtime')
    apply_export_check=$apply.Contains('provider export missing')
    launcher_debug=$launcher.Contains('artifacts\bin\Debug\net10.0\win-x64')
    launcher_no_forced_dlss=
        !$launcher.Contains(('$env:SHARPEMU_VK_UPSCALER'+[char]61+[char]39+'dlss'+[char]39))
    launcher_no_forced_quality=
        !$launcher.Contains(('$env:SHARPEMU_VK_UPSCALER_QUALITY'+[char]61))
}

foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.20] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.20] root_cause=Debug-executable-searches-Debug-provider-path-but-provider-was-only-deployed-to-Release'
Write-Host '[V74.0.67.2.20] fix=canonical-local-runtime+MSBuild-CopyToOutputDirectory-for-Debug-and-Release'
Write-Host '[V74.0.67.2.20] provider_rebuild=false'
Write-Host '[V74.0.67.2.20] provider_binary_modification=false'
Write-Host '[V74.0.67.2.20] powershell_51_compatible=true'

if($failed){throw '[V74.0.67.2.20] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.20] PACKAGE VALIDATION PASSED ($hashCount hashed files; $($scripts.Count) PowerShell files parsed; dual-config deployment checks passed)."
