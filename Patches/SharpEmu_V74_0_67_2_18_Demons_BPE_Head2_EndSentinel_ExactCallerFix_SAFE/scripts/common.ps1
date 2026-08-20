Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Capture the package root while common.ps1 is dot-sourced. This avoids
# dynamic $PSScriptRoot surprises in Windows PowerShell 5.1.
$script:SharpEmuPackageRootV74067218 = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-PackageRoot {
    return $script:SharpEmuPackageRootV74067218
}

function Get-RepoRoot {
    $package = Get-PackageRoot
    $cursor = Split-Path $package -Parent
    for ($i = 0; $i -lt 6; $i++) {
        if (Test-Path -LiteralPath (Join-Path $cursor 'src\SharpEmu.CLI\SharpEmu.CLI.csproj')) {
            return $cursor
        }
        $parent = Split-Path $cursor -Parent
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    throw "SharpEmu repository root not found above package: $package"
}

function Get-PatchesRoot {
    $repo = Get-RepoRoot
    $patches = Join-Path $repo 'Patches'
    if (!(Test-Path -LiteralPath $patches)) {
        New-Item -ItemType Directory -Force -Path $patches | Out-Null
    }
    return $patches
}

function Normalize-Lf([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Restore-Newlines([string]$Text) {
    return (Normalize-Lf $Text).Replace("`n", [Environment]::NewLine)
}

function Count-Ordinal {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Needle
    )
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count = 0
    $offset = 0
    while ($true) {
        $i = $Text.IndexOf($Needle, $offset, [StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $count++
        $offset = $i + $Needle.Length
    }
    return $count
}

function Find-CMake {
    $cmd = Get-Command cmake -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }

    $candidates = @(
        'C:\Program Files\CMake\bin\cmake.exe',
        'H:\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        "$env:ProgramFiles\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'cmake.exe not found.'
}

function Find-ReleaseHost {
    param([Parameter(Mandatory=$true)][string]$Repo)
    $items = @()
    foreach ($searchRoot in @(
        (Join-Path $Repo 'artifacts'),
        (Join-Path $Repo 'src\SharpEmu.CLI\bin')
    )) {
        if (Test-Path -LiteralPath $searchRoot) {
            $items += @(Get-ChildItem -LiteralPath $searchRoot -Filter SharpEmu.exe -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '[\\/]Release[\\/]' -and $_.FullName -match 'win-x64' })
        }
    }
    if ($items.Count -eq 0) { return $null }
    return @($items | Sort-Object LastWriteTimeUtc -Descending)[0]
}

function Try-DownloadOfficialFile {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][long]$MinimumBytes
    )
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination
        if ($existing.Length -ge $MinimumBytes) {
            Write-Host "[V74.0.67.2.15] Reusing cached dependency: $Destination"
            return $true
        }
        Remove-Item -LiteralPath $Destination -Force
    }

    try {
        Write-Host "[V74.0.67.2.15] Downloading official dependency: $Uri"
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
        if (!(Test-Path -LiteralPath $Destination)) { return $false }
        $downloaded = Get-Item -LiteralPath $Destination
        if ($downloaded.Length -lt $MinimumBytes) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            return $false
        }
        return $true
    }
    catch {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        Write-Warning "[V74.0.67.2.15] Download failed: $Uri"
        return $false
    }
}

function Stop-SharpEmuForBuild {
    $running = @(Get-Process SharpEmu -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }
    Write-Host "[V74.0.67.2.15] Stopping $($running.Count) running SharpEmu process(es) before build/deploy."
    $running | Stop-Process -Force
}

function Test-NativeExport {
    param(
        [Parameter(Mandatory=$true)][string]$DllPath,
        [Parameter(Mandatory=$true)][string]$ExportName
    )

    if (-not ('SharpEmuNativeProbeV7406728' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SharpEmuNativeProbeV7406728
{
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr LoadLibraryW(string lpFileName);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FreeLibrary(IntPtr hModule);
}
'@
    }

    $module = [SharpEmuNativeProbeV7406728]::LoadLibraryW($DllPath)
    if ($module -eq [IntPtr]::Zero) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "LoadLibraryW failed for $DllPath (Win32=$code)"
    }
    try {
        return [SharpEmuNativeProbeV7406728]::GetProcAddress($module, $ExportName) -ne [IntPtr]::Zero
    }
    finally {
        [void][SharpEmuNativeProbeV7406728]::FreeLibrary($module)
    }
}
