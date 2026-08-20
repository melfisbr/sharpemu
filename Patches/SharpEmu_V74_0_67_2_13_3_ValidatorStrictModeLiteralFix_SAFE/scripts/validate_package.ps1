. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){
    throw '[V74.0.67.2.13.3] SHA256SUMS.txt missing.'
}

$failed=$false
$hashCount=0

# 1) Full manifest/hash validation.
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){
        Write-Host "[V74.0.67.2.13.3] malformed_manifest_line=$line"
        $failed=$true
        continue
    }

    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative

    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.13.3] manifest_missing=$relative"
        $failed=$true
        continue
    }

    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.13.3] manifest_hash_mismatch=$relative"
        $failed=$true
    }
    $hashCount++
}

# 2) Parse every PowerShell file with the Windows PowerShell parser.
$scripts=Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File
$parseErrors=0
foreach($ps1 in $scripts){
    $tokens=$null
    $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,
        [ref]$tokens,
        [ref]$errors)
    if($errors.Count-ne 0){
        foreach($err in $errors){
            Write-Host "[V74.0.67.2.13.3] parse_error=$($ps1.Name):$($err.Message)"
            $parseErrors++
        }
        $failed=$true
    }
}
Write-Host "[V74.0.67.2.13.3] parsed_powershell_files=$($scripts.Count)"
Write-Host "[V74.0.67.2.13.3] powershell_parse_errors=$parseErrors"

# 3) StrictMode / PowerShell 5.1 safety scan.
$forbiddenPathApiShort='[IO.Path]::Get'+'RelativePath('
$forbiddenPathApiFull='[System.IO.Path]::Get'+'RelativePath('
# Fragmented so the validator itself does not embed the exact unsafe token.
$strictModeExpansionNeedle='"'+'$'+'b.Contains('

$reservedHostAssignments=0
$getRelativePathHits=0
$strictModeLiteralHits=0

foreach($ps1 in $scripts){
    $text=[IO.File]::ReadAllText($ps1.FullName)

    if([regex]::IsMatch($text,'(?im)^\s*\$host\s*=')){
        Write-Host "[V74.0.67.2.13.3] reserved_host_assignment=$($ps1.Name)"
        $reservedHostAssignments++
        $failed=$true
    }

    if($text.Contains($forbiddenPathApiShort) -or
       $text.Contains($forbiddenPathApiFull)){
        Write-Host "[V74.0.67.2.13.3] powershell51_getrelativepath=$($ps1.Name)"
        $getRelativePathHits++
        $failed=$true
    }

    if($text.Contains($strictModeExpansionNeedle)){
        Write-Host "[V74.0.67.2.13.3] strictmode_literal_expansion_risk=$($ps1.Name)"
        $strictModeLiteralHits++
        $failed=$true
    }
}

Write-Host "[V74.0.67.2.13.3] reserved_host_assignment_count=$reservedHostAssignments"
Write-Host "[V74.0.67.2.13.3] getrelativepath_hit_count=$getRelativePathHits"
Write-Host "[V74.0.67.2.13.3] strictmode_literal_expansion_risk_count=$strictModeLiteralHits"

# 4) Runner contracts.
$runnerMap=[ordered]@{
    'RUN_1_VALIDATE_PACKAGE.cmd'='validate_package.ps1'
    'RUN_2_PRECHECK.cmd'='precheck.ps1'
    'RUN_3_APPLY_BUILD.cmd'='apply_build.ps1'
    'RUN_4_DIAGNOSTIC.cmd'='diagnostic.ps1'
    'RUN_5_OPEN_GUI.cmd'='open_gui.ps1'
}

foreach($entry in $runnerMap.GetEnumerator()){
    $runner=Join-Path $package $entry.Key
    $script=Join-Path (Join-Path $package 'scripts') $entry.Value

    $runnerOk=Test-Path -LiteralPath $runner -PathType Leaf
    $scriptOk=Test-Path -LiteralPath $script -PathType Leaf
    $targetOk=$false

    if($runnerOk){
        $runnerText=[IO.File]::ReadAllText($runner)
        $targetOk=$runnerText.Contains(('scripts\'+$entry.Value))
    }

    Write-Host "[V74.0.67.2.13.3] runner_$($entry.Key)_exists=$($runnerOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.3] runner_$($entry.Key)_script_exists=$($scriptOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.3] runner_$($entry.Key)_target_ok=$($targetOk.ToString().ToLowerInvariant())"

    if(!$runnerOk -or !$scriptOk -or !$targetOk){$failed=$true}
}

# 5) Diagnostic telemetry ownership.
$diag=Normalize-Lf ([IO.File]::ReadAllText(
    (Join-Path $package 'scripts\diagnostic.ps1')))

$ownerNeedle=@'
$b.Contains('[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active')
'@
$wrongOwnerNeedle=@'
$b.Contains('[V74.0.67.2.13.3][UPSCALER][PROVIDER_INIT] state=active')
'@

$ownerOk=$diag.Contains($ownerNeedle)
$wrongOwnerAbsent=!$diag.Contains($wrongOwnerNeedle)

Write-Host "[V74.0.67.2.13.3] validator_active_telemetry_owner_v213=$($ownerOk.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.13.3] validator_wrong_package_owner_absent=$($wrongOwnerAbsent.ToString().ToLowerInvariant())"
if(!$ownerOk -or !$wrongOwnerAbsent){$failed=$true}

# 6) Cumulative implementation proof.
$dlssPatch=Normalize-Lf ([IO.File]::ReadAllText(
    (Join-Path $package 'scripts\patch_dlss_activation.ps1')))
$ramPatch=Normalize-Lf ([IO.File]::ReadAllText(
    (Join-Path $package 'scripts\patch_ram_pressure.ps1')))
$bpePatch=Normalize-Lf ([IO.File]::ReadAllText(
    (Join-Path $package 'scripts\patch_bpe_secondary_caller.ps1')))
$nativeCpp=Normalize-Lf ([IO.File]::ReadAllText(
    (Join-Path $package 'native\src\provider_dlss_ngx_vk.cpp')))

$checks=[ordered]@{
    dlss_v213_marker=$dlssPatch.Contains('V74.0.67.2.13 bounded provider activation retry')
    dlss_retry_timer=$dlssPatch.Contains('V74067213ProviderRetryMs = 2000')
    dlss_provider_retention=$dlssPatch.Contains('provider_loaded=1')
    ram_v213_marker=$ramPatch.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    ram_sparse_key=$ramPatch.Contains('ComputeV74067213LargeArrayContentKey')
    ram_v74064_ttl_owner=$ramPatch.Contains('ttl_owner=V74.0.64-multicache')
    bpe_v212_marker=$bpePatch.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    native_feature_common_info=$nativeCpp.Contains('NVSDK_NGX_FeatureCommonInfo g_feature_common_info')
    native_feature_path=$nativeCpp.Contains('PathListInfo.Path = g_feature_paths')
    native_create_dlss=$nativeCpp.Contains('NGX_VULKAN_CREATE_DLSS_EXT1')
    native_evaluate_dlss=$nativeCpp.Contains('NGX_VULKAN_EVALUATE_DLSS_EXT')
    native_last_error=$nativeCpp.Contains('sharpemu_vk_upscaler_get_last_error')
}
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.13.3] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.13.3] strict_mode_literal_strategy=fragmented-self-scan+single-quoted-owner-needles'
Write-Host '[V74.0.67.2.13.3] powershell_51_compatible=true'

if($failed){
    throw '[V74.0.67.2.13.3] PACKAGE VALIDATION FAILED.'
}
Write-Host "[V74.0.67.2.13.3] PACKAGE VALIDATION PASSED ($hashCount hashed files; $($scripts.Count) PowerShell files parsed; strict-mode/runner/ownership checks passed)."
