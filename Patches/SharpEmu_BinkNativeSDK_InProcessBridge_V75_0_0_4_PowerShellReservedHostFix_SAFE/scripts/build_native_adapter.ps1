Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot
$packageRoot = Get-PackageRoot

function Find-SdkRoot {
    $explicit =
        Environment.GetEnvironmentVariable(
            'SHARPEMU_BINK_SDK_ROOT')

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        $candidates.Add($explicit.Trim().Trim('"'))
    }

    $candidates.Add(
        (Join-Path $packageRoot 'ThirdParty\BinkSDK'))
    $candidates.Add(
        (Join-Path $repo 'ThirdParty\BinkSDK'))
    $candidates.Add(
        (Join-Path (
            Split-Path -Parent $packageRoot) 'BinkSDK'))

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }

        $header = @(
            Get-ChildItem -LiteralPath $candidate -Recurse -File `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ieq 'bink.h'
            }
        ) | Select-Object -First 1

        if ($null -ne $header) {
            return [ordered]@{
                Root = (Resolve-Path -LiteralPath $candidate).Path
                Header = $header.FullName
            }
        }
    }

    return $null
}

function Find-BinkLibrary([string]$SdkRoot) {
    $libraries = @(
        Get-ChildItem -LiteralPath $SdkRoot -Recurse -File `
            -Filter '*.lib' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '(?i)bink' -and
            $_.FullName -match '(?i)(x64|win64|windows|redist|lib)'
        }
    )

    if ($libraries.Count -eq 0) {
        $libraries = @(
            Get-ChildItem -LiteralPath $SdkRoot -Recurse -File `
                -Filter '*.lib' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '(?i)bink'
            }
        )
    }

    if ($libraries.Count -eq 0) {
        return $null
    }

    return (
        $libraries |
        Sort-Object @{
            Expression = {
                if ($_.FullName -match '(?i)(x64|win64)') { 0 } else { 1 }
            }
        }, Name |
        Select-Object -First 1
    ).FullName
}

function Find-VsDevCmd {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} `
        'Microsoft Visual Studio\Installer\vswhere.exe'

    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $install = & $vswhere `
            -latest `
            -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath

        if (-not [string]::IsNullOrWhiteSpace($install)) {
            $candidate = Join-Path $install.Trim() `
                'Common7\Tools\VsDevCmd.bat'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    return $null
}

$sdk = Find-SdkRoot
if ($null -eq $sdk) {
    Write-Step "NativeAdapterBuild=SKIPPED"
    Write-Step "NativeSdkRoot=NOT_FOUND"
    Write-Step "Action=Set SHARPEMU_BINK_SDK_ROOT to a licensed Windows x64 Bink SDK, then run RUN_5_BUILD_NATIVE_ADAPTER.cmd."
    exit 0
}

$library = Find-BinkLibrary $sdk.Root
if ([string]::IsNullOrWhiteSpace($library)) {
    throw "$script:Tag Bink SDK found but no Bink .lib was located under '$($sdk.Root)'."
}

$vsDevCmd = Find-VsDevCmd
if ([string]::IsNullOrWhiteSpace($vsDevCmd)) {
    throw "$script:Tag Visual Studio C++ x64 Build Tools were not found."
}

$headerText = Get-Content -LiteralPath $sdk.Header -Raw
foreach ($apiName in @(
    'BinkOpen',
    'BinkWait',
    'BinkDoFrame',
    'BinkCopyToBuffer',
    'BinkNextFrame',
    'BinkClose'
)) {
    if ($headerText.IndexOf(
            $apiName,
            [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Supplied bink.h does not contain required API '$apiName'."
    }
}

$defines = @()
if ($headerText.IndexOf(
        'BinkSoundUseXAudio2',
        [StringComparison]::Ordinal) -ge 0) {
    $defines += '/DSHARPEMU_BINK_HAVE_XAUDIO2=1'
}

$source = Join-Path $packageRoot `
    'source\native\SharpEmu.BinkNative.cpp'
$stage = Join-Path $packageRoot '.native-stage'
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$output = Join-Path $stage 'SharpEmu.BinkNative.dll'
$object = Join-Path $stage 'SharpEmu.BinkNative.obj'
$cmdFile = Join-Path $stage 'build_native_adapter.cmd'

$includeDir = Split-Path -Parent $sdk.Header

$command = @"
@echo off
call "$vsDevCmd" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b %errorlevel%
cl.exe /nologo /LD /O2 /EHsc /std:c++17 /utf-8 $($defines -join ' ') /I"$includeDir" /Fo"$object" "$source" "$library" /link /OUT:"$output"
exit /b %errorlevel%
"@

Set-Content -LiteralPath $cmdFile -Value $command -Encoding ASCII

Write-Step "NativeSdkRoot=$($sdk.Root)"
Write-Step "NativeHeader=$($sdk.Header)"
Write-Step "NativeLibrary=$library"
Write-Step "VsDevCmd=$vsDevCmd"
Write-Step "XAudio2SdkProvider=$($defines.Count -gt 0)"

& cmd.exe /d /s /c "`"$cmdFile`""
if ($LASTEXITCODE -ne 0) {
    throw "$script:Tag Native adapter build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "$script:Tag Native adapter build reported success but DLL was not created."
}

$deployDirs = @(
    Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2',
    Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2'
)

foreach ($deployDir in $deployDirs) {
    New-Item -ItemType Directory -Force -Path $deployDir | Out-Null
    Copy-Item -LiteralPath $output -Destination (
        Join-Path $deployDir 'SharpEmu.BinkNative.dll') -Force
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash
Write-Step "NativeAdapterBuild=PASSED"
Write-Step "NativeAdapter=$output"
Write-Step "NativeAdapterSHA256=$hash"
Write-Step "RuntimeMode=native-rad becomes available; current rad default auto-prefers it unless SHARPEMU_BINK_NATIVE_PREFER=0."
