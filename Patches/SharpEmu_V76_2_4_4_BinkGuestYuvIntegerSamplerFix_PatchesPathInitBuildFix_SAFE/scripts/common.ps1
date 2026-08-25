$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Tag = 'V76.2.4.4-BINK-GUEST-YUV-INTEGER-SAMPLER-PATCHES-PATH-INIT-BUILDFIX'
$PackageRoot = Split-Path -Parent $PSScriptRoot
$PatchesRoot = Split-Path -Parent $PackageRoot
$TargetPackage = Join-Path $PatchesRoot 'SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE'
$TargetScript = Join-Path $TargetPackage 'scripts\patch_target.ps1'
$TargetRunner = Join-Path $TargetPackage 'RUN_2_PATCH_AND_REVALIDATE_V76_2_4.cmd'
$Marker = 'V76.2.4.4 PATCHES_ROOT_INIT'

function Write-Tag([string]$Message) {
    Write-Host "[$Tag] $Message"
}

function Get-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo ausente: $Path"
    }
    return [System.IO.File]::ReadAllText($Path)
}

function Set-TextUtf8NoBom([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Get-TargetState {
    if (-not (Test-Path -LiteralPath $TargetScript)) { return 'MissingTargetScript' }
    if (-not (Test-Path -LiteralPath $TargetRunner)) { return 'MissingTargetRunner' }

    $targetText = Get-Text $TargetScript
    if ($targetText.Contains($Marker)) {
        if ($targetText -match 'Join-Path\s+\$Patches\b') {
            return 'Partial'
        }
        if ($targetText -notmatch '\$v7624PatchesRoot\s*=\s*Split-Path\s+-Parent\s+\(Split-Path\s+-Parent\s+\$PSScriptRoot\)') {
            return 'Partial'
        }
        return 'Applied'
    }

    if ($targetText -match 'Join-Path\s+\$Patches\b') {
        return 'Ready'
    }

    return 'Divergent'
}

function Assert-TargetReadyOrApplied {
    $state = Get-TargetState
    if ($state -notin @('Ready','Applied')) {
        throw "Target state inválido: $state Target=$TargetScript"
    }
    return $state
}
