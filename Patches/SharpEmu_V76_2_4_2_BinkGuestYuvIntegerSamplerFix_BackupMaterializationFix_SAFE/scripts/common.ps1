Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Tag = '[V76.2.4.2-BINK-GUEST-YUV-INTEGER-SAMPLER-BACKUP-MATERIALIZATION-FIX]'
$Repo = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches = Join-Path $Repo 'Patches'
$TargetPackageName = 'SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE'
$TargetPackageDir = Join-Path $Patches $TargetPackageName
$TargetScript = Join-Path $TargetPackageDir 'scripts\patch_target.ps1'
$Marker = 'V76.2.4.2-BACKUP-MATERIALIZATION'

function Assert-TargetPackage {
    if (-not (Test-Path -LiteralPath $Patches -PathType Container)) { throw "Patches ausente: $Patches" }
    if (-not (Test-Path -LiteralPath $TargetPackageDir -PathType Container)) { throw "Pacote alvo V76.2.4.1 não encontrado: $TargetPackageDir" }
    if (-not (Test-Path -LiteralPath $TargetScript -PathType Leaf)) { throw "patch_target.ps1 ausente: $TargetScript" }
}

function Get-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Utf8NoBom([string]$Path,[string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Text,$enc)
}

function Assert-PowerShellParses([string]$Path) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $msg = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell parse failed: $Path :: $msg"
    }
}

function Get-RepairRunner {
    $candidates = @(Get-ChildItem -LiteralPath $TargetPackageDir -Filter 'RUN_*.cmd' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($candidate in $candidates) {
        $content = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match '(?i)patch_target\.ps1') { return $candidate.FullName }
    }
    return $null
}
