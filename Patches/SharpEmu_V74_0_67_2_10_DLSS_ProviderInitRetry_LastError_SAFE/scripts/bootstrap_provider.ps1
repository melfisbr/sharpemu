. (Join-Path $PSScriptRoot 'common.ps1')
$patches = Get-PatchesRoot
$package = Get-PackageRoot
$cmake = Find-CMake

function Invoke-NativeLoggedV74067210 {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$Label,
        [switch]$Append
    )

    # PowerShell 5.1 represents native stderr as ErrorRecord objects.
    # A harmless CMake warning must not terminate solely because the package
    # uses ErrorActionPreference=Stop. The native exit code is authoritative.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $captured = @(& $FilePath @Arguments 2>&1)
        $nativeExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $textLines = @(
        foreach ($item in $captured) {
            if ($null -eq $item) { continue }
            $text = $item.ToString()
            Write-Host $text
            $text
        }
    )

    if ($Append) {
        if ($textLines.Count -gt 0) {
            $textLines | Add-Content -LiteralPath $LogPath -Encoding UTF8
        }
    }
    else {
        $textLines | Set-Content -LiteralPath $LogPath -Encoding UTF8
    }

    Write-Host "[V74.0.67.2.10] native_command_label=$Label exit_code=$nativeExit stderr_policy=exit-code-authoritative"

    if ($nativeExit -ne 0) {
        throw "$Label failed: native exit $nativeExit"
    }

    return $nativeExit
}


$vendorRoot = Join-Path $patches '_vendor'
$ngxRoot = Join-Path $vendorRoot 'NVIDIA_DLSS_v310_7_0'
$vulkanHeaders = Join-Path $vendorRoot 'Vulkan-Headers'
New-Item -ItemType Directory -Force -Path $vendorRoot | Out-Null

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) { throw 'git.exe is required to prepare the official SDK headers.' }

if (!(Test-Path -LiteralPath (Join-Path $ngxRoot 'include\nvsdk_ngx_vk.h'))) {
    if (Test-Path -LiteralPath $ngxRoot) {
        Remove-Item -LiteralPath $ngxRoot -Recurse -Force
    }

    $oldSkip = $env:GIT_LFS_SKIP_SMUDGE
    try {
        $env:GIT_LFS_SKIP_SMUDGE = '1'
        & $git.Source clone --depth 1 --branch v310.7.0 https://github.com/NVIDIA/DLSS.git $ngxRoot
        if ($LASTEXITCODE -ne 0) {
            throw "NVIDIA/DLSS v310.7.0 clone failed: exit $LASTEXITCODE"
        }
    }
    finally {
        $env:GIT_LFS_SKIP_SMUDGE = $oldSkip
    }
}
else {
    Write-Host '[V74.0.67.2.10] Reusing NVIDIA DLSS v310.7.0 header cache.'
}

if (!(Test-Path -LiteralPath (Join-Path $vulkanHeaders 'include\vulkan\vulkan.h'))) {
    if (Test-Path -LiteralPath $vulkanHeaders) {
        Remove-Item -LiteralPath $vulkanHeaders -Recurse -Force
    }

    & $git.Source clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git $vulkanHeaders
    if ($LASTEXITCODE -ne 0) {
        throw "Khronos Vulkan-Headers clone failed: exit $LASTEXITCODE"
    }
}
else {
    Write-Host '[V74.0.67.2.10] Reusing Vulkan-Headers cache.'
}

$ngxHeader = Join-Path $ngxRoot 'include\nvsdk_ngx_vk.h'
$ngxDefs = Join-Path $ngxRoot 'include\nvsdk_ngx_defs.h'
foreach ($required in @($ngxHeader, $ngxDefs)) {
    if (!(Test-Path -LiteralPath $required)) {
        throw "Required NVIDIA SDK header missing: $required"
    }
}

$headerText = [IO.File]::ReadAllText($ngxHeader)
foreach ($api in @(
    'NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements',
    'NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements',
    'NVSDK_NGX_VULKAN_GetFeatureRequirements',
    'NVSDK_NGX_VULKAN_Init_with_ProjectID',
    'NVSDK_NGX_VULKAN_GetCapabilityParameters'
)) {
    if (!$headerText.Contains($api)) {
        throw "NVIDIA SDK cache does not expose required Vulkan NGX API: $api"
    }
}

# 310.7.0 uses the Khronos-specific static import library. Preserve the
# earlier legacy path as a compatibility fallback for an already-cached SDK.
$ngxLibKhr = Join-Path $ngxRoot 'lib\Windows_x86_64\khr\x64\nvsdk_ngx_khr_s.lib'
$ngxLibLegacy = Join-Path $ngxRoot 'lib\Windows_x86_64\x64\nvsdk_ngx_s.lib'

if (!(Test-Path -LiteralPath $ngxLibKhr) -or
    (Get-Item -LiteralPath $ngxLibKhr -ErrorAction SilentlyContinue).Length -lt 100000) {
    [void](Try-DownloadOfficialFile `
        -Uri 'https://github.com/NVIDIA/DLSS/raw/refs/tags/v310.7.0/lib/Windows_x86_64/khr/x64/nvsdk_ngx_khr_s.lib' `
        -Destination $ngxLibKhr `
        -MinimumBytes 100000)
}

$ngxLib = $null
foreach ($candidate in @($ngxLibKhr, $ngxLibLegacy)) {
    if (Test-Path -LiteralPath $candidate) {
        $item = Get-Item -LiteralPath $candidate
        if ($item.Length -ge 100000) {
            $ngxLib = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ngxLib)) {
    $legacyDownloaded = Try-DownloadOfficialFile `
        -Uri 'https://github.com/NVIDIA/DLSS/raw/refs/tags/v310.7.0/lib/Windows_x86_64/x64/nvsdk_ngx_s.lib' `
        -Destination $ngxLibLegacy `
        -MinimumBytes 100000

    if ($legacyDownloaded) {
        $ngxLib = $ngxLibLegacy
    }
}

if ([string]::IsNullOrWhiteSpace($ngxLib) -or !(Test-Path -LiteralPath $ngxLib)) {
    throw 'Unable to obtain the official NVIDIA NGX Vulkan static library.'
}

$ngxDll = Join-Path $ngxRoot 'lib\Windows_x86_64\rel\nvngx_dlss.dll'
if (!(Test-Path -LiteralPath $ngxDll) -or
    (Get-Item -LiteralPath $ngxDll -ErrorAction SilentlyContinue).Length -lt 10000000) {
    $downloaded = Try-DownloadOfficialFile `
        -Uri 'https://github.com/NVIDIA/DLSS/raw/refs/tags/v310.7.0/lib/Windows_x86_64/rel/nvngx_dlss.dll' `
        -Destination $ngxDll `
        -MinimumBytes 10000000
    if (!$downloaded) {
        throw 'Unable to obtain official nvngx_dlss.dll v310.7.0.'
    }
}

$buildDir = Join-Path $patches '_native_build\V74_0_67_2_10_dlss'
if (Test-Path -LiteralPath $buildDir) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog = Join-Path $patches "SharpEmu_V74_0_67_2_10_DLSS_PROVIDER_BUILD_$stamp.log"

Write-Host '[V74.0.67.2.10] Configuring consolidated NVIDIA NGX Vulkan provider...'
$configureArgs = @(
    '-S', (Join-Path $package 'native'),
    '-B', $buildDir,
    '-A', 'x64',
    "-DNGX_SDK_ROOT=$ngxRoot",
    "-DVULKAN_HEADERS_ROOT=$vulkanHeaders",
    "-DNGX_LIBRARY=$ngxLib"
)
[void](Invoke-NativeLoggedV74067210 `
    -FilePath $cmake `
    -Arguments $configureArgs `
    -LogPath $buildLog `
    -Label 'CMake configure')

$vcxproj = Join-Path $buildDir 'SharpEmu.VulkanUpscaler.Native.vcxproj'
if (!(Test-Path -LiteralPath $vcxproj)) {
    throw "Generated vcxproj missing: $vcxproj"
}
$projectXml = [IO.File]::ReadAllText($vcxproj)
$releaseMt = $projectXml -match '<RuntimeLibrary>MultiThreaded</RuntimeLibrary>'
$releaseMd = $projectXml -match '<RuntimeLibrary>MultiThreadedDLL</RuntimeLibrary>'
Write-Host "[V74.0.67.2.10] generated_runtime_mt=$($releaseMt.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.10] generated_runtime_md=$($releaseMd.ToString().ToLowerInvariant())"
if (!$releaseMt -or $releaseMd) {
    throw 'Generated MSVC project did not use static CRT /MT.'
}

Write-Host '[V74.0.67.2.10] Building consolidated DLSS NGX provider Release...'
$nativeBuildArgs = @(
    '--build', $buildDir,
    '--config', 'Release'
)
[void](Invoke-NativeLoggedV74067210 `
    -FilePath $cmake `
    -Arguments $nativeBuildArgs `
    -LogPath $buildLog `
    -Label 'CMake provider build' `
    -Append)

$provider = Get-ChildItem -LiteralPath $buildDir -Filter 'SharpEmu.VulkanUpscaler.Native.dll' -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -ExpandProperty FullName -First 1

if ([string]::IsNullOrWhiteSpace($provider) -or !(Test-Path -LiteralPath $provider)) {
    throw 'Provider build succeeded but SharpEmu.VulkanUpscaler.Native.dll was not found.'
}

$infoPath = Join-Path $patches 'SharpEmu_V74_0_67_2_10_DLSS_PROVIDER_BUILD.txt'
@(
    "NGX_ROOT=$ngxRoot",
    "NGX_LIBRARY=$ngxLib",
    "NGX_DLL=$ngxDll",
    "VULKAN_HEADERS=$vulkanHeaders",
    "PROVIDER=$provider",
    "MSVC_RUNTIME=MultiThreaded",
    "MSVC_FLAG=/MT",
    "PROVIDER_BUILD_LOG=$buildLog"
) | Set-Content -LiteralPath $infoPath -Encoding UTF8

Write-Host "[V74.0.67.2.10] PROVIDER_BUILD=$provider"
Write-Host "[V74.0.67.2.10] NGX_LIBRARY=$ngxLib"
Write-Host "[V74.0.67.2.10] NGX_DLL=$ngxDll"
Write-Host '[V74.0.67.2.10] PROVIDER BUILD PASSED.'
