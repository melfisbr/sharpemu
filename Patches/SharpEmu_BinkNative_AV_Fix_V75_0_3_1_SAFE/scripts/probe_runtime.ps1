param([string]$RuntimeDll='')
. (Join-Path $PSScriptRoot 'common.ps1')

$required=@('BinkOpen','BinkClose','BinkWait','BinkDoFrame','BinkCopyToBuffer','BinkNextFrame','BinkSetSoundSystem')
$audio=@('BinkOpenXAudio29','BinkOpenXAudio28','BinkOpenXAudio2','BinkOpenXAudio27','BinkOpenWaveOut','BinkOpenDirectSound')

function Test-RuntimeCandidate([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    $full=[IO.Path]::GetFullPath($Path)
    $machine=Get-PeMachine $full
    if ($machine -ne 0x8664) {
        Write-Tag ("SKIP non-AMD64 machine=0x{0:X4} path={1}" -f $machine,$full)
        return $null
    }

    $exports=Test-Exports $full $required $audio
    if ($exports.Known) {
        if (-not $exports.RequiredOk) {
            Write-Tag "SKIP missing required Bink video/control exports path=$full"
            return $null
        }
        if (-not $exports.AnyOk) {
            Write-Tag "SKIP no supported native Bink audio backend export path=$full"
            return $null
        }
    } else {
        Write-Tag 'WARNING dumpbin unavailable; architecture verified and exports will be checked by adapter at runtime'
    }

    return $full
}

$p=''
$arg=$RuntimeDll
if (-not [string]::IsNullOrWhiteSpace($arg)) {
    $arg=$arg.Trim().Trim('"')
    if (Test-Path -LiteralPath $arg -PathType Leaf) {
        $candidate=Test-RuntimeCandidate $arg
        if ($candidate) { $p=$candidate }
    }
    elseif (Test-Path -LiteralPath $arg -PathType Container) {
        Write-Tag "Scanning folder recursively for compatible AMD64 Bink runtime: $arg"
        $dlls=@(Get-ChildItem -LiteralPath $arg -Recurse -File -Filter '*.dll' -ErrorAction SilentlyContinue | Sort-Object FullName)
        foreach($dll in $dlls) {
            $candidate=Test-RuntimeCandidate $dll.FullName
            if ($candidate) { $p=$candidate; break }
        }
    }
    else {
        throw "$script:Tag runtime path does not exist: $arg"
    }
}

if ([string]::IsNullOrWhiteSpace($p)) {
    $auto=Find-Runtime ''
    if (-not [string]::IsNullOrWhiteSpace($auto)) {
        $candidate=Test-RuntimeCandidate $auto
        if ($candidate) { $p=$candidate }
    }
}

if ([string]::IsNullOrWhiteSpace($p)) {
    throw "$script:Tag no compatible AMD64 Bink2 runtime found. Supply a real DLL or extracted folder, for example: RUN_4_PROBE_RUNTIME.cmd 'C:\Bink2\bink2w64.dll'"
}

foreach($d in Get-DeployDirs) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $dst=Join-Path $d 'bink2w64.dll'
    if (-not [string]::Equals([IO.Path]::GetFullPath($p),[IO.Path]::GetFullPath($dst),[StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $p -Destination $dst -Force
    }
}

$env:SHARPEMU_BINK_RUNTIME_DLL=$p
Write-Tag "RUNTIME READY path=$p sha=$(Get-Sha $p) machine=AMD64"
