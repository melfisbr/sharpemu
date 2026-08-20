Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Tag = '[V74.0.77.2.1]'
$script:PackageRoot = (Split-Path -Parent $PSScriptRoot)
$script:PatchesRoot = (Split-Path -Parent $script:PackageRoot)
$script:TargetPackageName = 'SharpEmu_DemonsSouls_AttractGuestStateCompletion_Fix_V74_0_77_2_SAFE'
$script:TargetPackage = Join-Path $script:PatchesRoot $script:TargetPackageName
$script:TargetRel = 'scripts\run_test.ps1'
$script:Target = Join-Path $script:TargetPackage $script:TargetRel
$script:Marker = 'V74.0.77.2.1 PS51 ProcessStartInfo.Arguments compatibility'

function Assert-Target {
    if (-not (Test-Path -LiteralPath $script:Target -PathType Leaf)) {
        throw "$script:Tag Arquivo alvo nao encontrado: $script:Target"
    }
}

function Get-TargetText {
    Assert-Target
    return [System.IO.File]::ReadAllText($script:Target)
}

function Get-LauncherState {
    $text = Get-TargetText
    $old = ([regex]::Matches($text, '(?i)\.ArgumentList\.Add\s*\(')).Count
    $new = ([regex]::Matches($text, '(?i)Add-PS51ProcessArgument\s+-Psi\s+\$psi')).Count
    $marker = $text.Contains($script:Marker)
    $psi = ([regex]::Matches($text, '(?i)ProcessStartInfo')).Count
    [pscustomobject]@{ OldCalls=$old; NewCalls=$new; Marker=$marker; ProcessStartInfoRefs=$psi }
}

function Test-PowerShellParse([string]$Path) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "$script:Tag PowerShell parse failure: $Path :: $msg"
    }
}

function Write-State {
    $s = Get-LauncherState
    Write-Host "$script:Tag Target=$script:Target"
    Write-Host "$script:Tag ArgumentListAdd=$($s.OldCalls) PS51Add=$($s.NewCalls) Marker=$($s.Marker) ProcessStartInfoRefs=$($s.ProcessStartInfoRefs)"
    return $s
}
