Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Tag = "V76.2.4.7-BINK-GUEST-YUV-INTEGER-SAMPLER-CANONICAL-CONTAINMENT-BUILDFIX"
$script:PackageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:PatchesRoot = [IO.Directory]::GetParent($script:PackageRoot).FullName
$script:TargetV6Root = Join-Path $script:PatchesRoot "SharpEmu_V76_2_4_6_BinkGuestYuvIntegerSamplerFix_SplitPathCompleteGuard_SAFE"
$script:TargetV1Root = Join-Path $script:PatchesRoot "SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE"
$script:TargetV6Manifest = Join-Path $script:TargetV6Root "manifest.sha256"
$script:ResultSummary = Join-Path $script:PatchesRoot ("SharpEmu_V76_2_4_7_SUMMARY_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Tag([string]$Message) { Write-Host "[$script:Tag] $Message" }

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-PowerShellParses([string]$Path) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { $_.Message }) -join "; "
        throw "PowerShell parse failed: $Path :: $msg"
    }
}

function Get-TargetGuardScript {
    if (-not (Test-Path -LiteralPath $script:TargetV6Root -PathType Container)) {
        throw "Pacote-alvo V76.2.4.6 ausente: $script:TargetV6Root"
    }
    $matches = @()
    Get-ChildItem -LiteralPath (Join-Path $script:TargetV6Root "scripts") -Filter "*.ps1" -File | ForEach-Object {
        $txt = [IO.File]::ReadAllText($_.FullName)
        if ($txt.IndexOf('Path fora do pacote-alvo:', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matches += $_.FullName
        }
    }
    if ($matches.Count -ne 1) {
        throw "Esperado exatamente 1 script da V76.2.4.6 com guard 'Path fora do pacote-alvo'; encontrados=$($matches.Count)"
    }
    return $matches[0]
}

function Get-ContainmentState([string]$Path) {
    $txt = [IO.File]::ReadAllText($Path)
    if ($txt.Contains('[V76.2.4.7-CANONICAL-CONTAINMENT]')) { return 'Applied' }
    if ($txt.IndexOf('Path fora do pacote-alvo:', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'Ready' }
    return 'Divergent'
}

function Update-TargetManifest([string]$ChangedFile) {
    if (-not (Test-Path -LiteralPath $script:TargetV6Manifest -PathType Leaf)) {
        throw "manifest da V76.2.4.6 ausente: $script:TargetV6Manifest"
    }
    $rel = [IO.Path]::GetRelativePath($script:TargetV6Root, $ChangedFile).Replace('\','/')
    $hash = Get-Sha256 $ChangedFile
    $lines = [Collections.Generic.List[string]]::new()
    $found = $false
    foreach($line in [IO.File]::ReadAllLines($script:TargetV6Manifest)) {
        if ($line -match '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
            $entry = $Matches[2].Replace('\','/')
            if ([string]::Equals($entry, $rel, [StringComparison]::OrdinalIgnoreCase)) {
                $lines.Add("$hash *$rel")
                $found = $true
                continue
            }
        }
        $lines.Add($line)
    }
    if (-not $found) { throw "Entrada de manifest não encontrada para $rel" }
    [IO.File]::WriteAllLines($script:TargetV6Manifest, $lines, [Text.UTF8Encoding]::new($false))
}
