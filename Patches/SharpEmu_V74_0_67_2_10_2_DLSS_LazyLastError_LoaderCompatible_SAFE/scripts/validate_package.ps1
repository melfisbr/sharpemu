. (Join-Path $PSScriptRoot 'common.ps1')
$package = Get-PackageRoot
$manifest = Join-Path $package 'SHA256SUMS.txt'

if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw 'SHA256SUMS.txt missing.'
}

$lines = @(Get-Content -LiteralPath $manifest)
$checked = 0
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw "Malformed manifest line: $line"
    }

    $expected = $matches[1].ToUpperInvariant()
    $relative = $matches[2]
    $path = Join-Path $package $relative
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Manifest file missing: $relative"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "SHA256 mismatch: $relative"
    }
    $checked++
}

# Parse every package PowerShell script with the Windows PowerShell parser.
$parseErrors = New-Object System.Collections.Generic.List[string]
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$tokens,
        [ref]$errors)
    foreach ($err in @($errors)) {
        $parseErrors.Add("$($script.Name): $($err.Message)")
    }
}
if ($parseErrors.Count -ne 0) {
    throw ("PowerShell parse errors:`n" + ($parseErrors -join "`n"))
}

$provider = Join-Path $package 'native\src\provider_dlss_ngx_vk.cpp'
$header = Join-Path $package 'native\include\sharpemu_vulkan_upscaler.h'
$cmake = Join-Path $package 'native\CMakeLists.txt'
foreach ($path in @($provider, $header, $cmake)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Native package file missing: $path" }
}

$cpp = [IO.File]::ReadAllText($provider)
$cmakeText = [IO.File]::ReadAllText($cmake)

$nativeChecks = [ordered]@{
    feature_instance_extensions =
        $cpp.Contains('NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements')
    feature_device_extensions =
        $cpp.Contains('NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements')
    feature_requirements =
        $cpp.Contains('NVSDK_NGX_VULKAN_GetFeatureRequirements')
    deprecated_required_extensions_absent =
        !$cpp.Contains('NVSDK_NGX_VULKAN_RequiredExtensions')
    init_project_id =
        $cpp.Contains('NVSDK_NGX_VULKAN_Init_with_ProjectID')
    capability_parameters =
        $cpp.Contains('NVSDK_NGX_VULKAN_GetCapabilityParameters')
    create_dlss =
        $cpp.Contains('NGX_VULKAN_CREATE_DLSS_EXT1')
    evaluate_dlss =
        $cpp.Contains('NGX_VULKAN_EVALUATE_DLSS_EXT')
    vulkan_resource_wrap =
        $cpp.Contains('NVSDK_NGX_Create_ImageView_Resource_VK')
    serialized_ngx =
        $cpp.Contains('std::mutex g_mutex') -and
        $cpp.Contains('std::lock_guard<std::mutex>')
    init_failure_returns_failure =
        $cpp.Contains('if (NVSDK_NGX_FAILED(init))') -and
        $cpp.Contains('return -4;')
    static_crt =
        $cmakeText.Contains('MSVC_RUNTIME_LIBRARY "MultiThreaded"')
    provider_name =
        $cmakeText.Contains('SharpEmu.VulkanUpscaler.Native')
}

foreach ($entry in $nativeChecks.GetEnumerator()) {
    Write-Host "[V74.0.67.2.10.2] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if (!$entry.Value) {
        throw "Native structural validator failed: $($entry.Key)"
    }
}

# No title-specific guest resource addresses are permitted in the patch.
foreach ($forbidden in @(
    '0x492E50000',
    '0x45F580000',
    '0x464710000',
    '0x463810000',
    '0x457C00000'
)) {
    foreach ($file in @(
        $provider,
        (Join-Path $package 'scripts\patch_source.ps1')
    )) {
        if ([IO.File]::ReadAllText($file).Contains($forbidden)) {
            throw "Hardcoded observed guest resource address found: $forbidden in $file"
        }
    }
}

# Windows PowerShell 5.1 compatibility guard.
#
# V74.0.67.2.10.2 self-scan fix:
# build forbidden method names from fragments so this validator can scan
# itself without embedding the exact forbidden invocation in its own source.
$forbiddenPathApiShort = '[IO.Path]::Get' + 'RelativePath('
$forbiddenPathApiFull = '[System.IO.Path]::Get' + 'RelativePath('

foreach ($script in Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File) {
    $text = [IO.File]::ReadAllText($script.FullName)

    if ($text.Contains($forbiddenPathApiShort) -or
        $text.Contains($forbiddenPathApiFull)) {
        throw "PowerShell 5.1 incompatible relative-path API in $($script.Name)"
    }

    if ($text -match '(?im)^\s*\$host\s*=') {
        throw "Reserved PowerShell variable `$host assigned in $($script.Name)"
    }
}

$readme = Join-Path $package 'README.txt'
$relativeReadme = (New-Object System.Uri((Resolve-Path $package).Path + '\')).MakeRelativeUri(
    (New-Object System.Uri((Resolve-Path $readme).Path))).ToString().Replace('/', '\')

Write-Host '[V74.0.67.2.10.2] validator_self_scan_strategy=dynamic-fragmented-token'
Write-Host '[V74.0.67.2.10.2] validator_self_scan_false_positive_fixed=true'
Write-Host "[V74.0.67.2.10.2] validator_readme_relative=$relativeReadme"
Write-Host "[V74.0.67.2.10.2] package_root=$package"
Write-Host '[V74.0.67.2.10.2] relative_path_engine=System.Uri.MakeRelativeUri'
Write-Host '[V74.0.67.2.10.2] powershell_51_compatible=true'
Write-Host "[V74.0.67.2.10.2] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; native NGX/Vulkan integration structurally verified)."
