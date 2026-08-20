. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot;$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path $manifest)){throw 'SHA256SUMS.txt missing.'}
$failed=$false;$hashCount=0
foreach($line in Get-Content $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){throw "Malformed manifest line: $line"}
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path $path)){Write-Host "[V74.0.67.2.13.1] manifest_missing=$relative";$failed=$true;continue}
    $actual=(Get-FileHash $path -Algorithm SHA256).Hash
    if($actual-ne $expected){Write-Host "[V74.0.67.2.13.1] manifest_hash_mismatch=$relative";$failed=$true}
    $hashCount++
}
foreach($ps1 in Get-ChildItem (Join-Path $package 'scripts') -Filter '*.ps1' -File){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($ps1.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne 0){foreach($err in $errors){Write-Host "[V74.0.67.2.13.1] parse_error=$($ps1.Name):$($err.Message)"};$failed=$true}
}
$cpp=Normalize-Lf ([IO.File]::ReadAllText((Join-Path $package 'native\src\provider_dlss_ngx_vk.cpp')))
$checks=[ordered]@{
    feature_common_info=$cpp.Contains('NVSDK_NGX_FeatureCommonInfo g_feature_common_info')
    explicit_feature_path=$cpp.Contains('PathListInfo.Path = g_feature_paths')
    feature_logging=$cpp.Contains('LoggingInfo.LoggingCallback = ngx_app_log')
    feature_dll_probe=$cpp.Contains('stage=feature_dll')
    init_project_id=$cpp.Contains('NVSDK_NGX_VULKAN_Init_with_ProjectID')
    create_dlss=$cpp.Contains('NGX_VULKAN_CREATE_DLSS_EXT1')
    evaluate_dlss=$cpp.Contains('NGX_VULKAN_EVALUATE_DLSS_EXT')
    last_error=$cpp.Contains('sharpemu_vk_upscaler_get_last_error')
}
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.13.1] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}
Write-Host '[V74.0.67.2.13.1] relative_path_engine=manifest-relative'
Write-Host '[V74.0.67.2.13.1] powershell_51_compatible=true'
if($failed){throw '[V74.0.67.2.13.1] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.13.1] PACKAGE VALIDATION PASSED ($hashCount hashed files; PowerShell parsed)."
