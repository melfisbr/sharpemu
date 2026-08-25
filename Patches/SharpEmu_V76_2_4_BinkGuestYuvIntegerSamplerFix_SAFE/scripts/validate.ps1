param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$tag='V76.2.4-BINK-GUEST-YUV-INTEGER-SAMPLER-FIX'
$manifest=Join-Path $PackageRoot 'manifest.sha256'
# V76.2.4.1 VALIDATOR PATH FIX: derive package root only from this script location.
$root = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..')).Trim()
$manifest = [IO.Path]::Combine($root, 'manifest.sha256')
if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($manifest)) {
    throw 'V76.2.4.1 package-root/manifest resolution failed'
}
# V76.2.4.1 VALIDATOR PATH FIX: derive package root only from this script location.
$root = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..')).Trim()
$manifest = [IO.Path]::Combine($root, 'manifest.sha256')
if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($manifest)) {
    throw 'V76.2.4.1 package-root/manifest resolution failed'
}
# V76.2.4.1 VALIDATOR PATH FIX: derive package root only from this script location.
$root = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..')).Trim()
$manifest = [IO.Path]::Combine($root, 'manifest.sha256')
if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($manifest)) {
    throw 'V76.2.4.1 package-root/manifest resolution failed'
}
# V76.2.4.1 VALIDATOR PATH FIX: derive package root only from this script location.
$root = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..')).Trim()
$manifest = [IO.Path]::Combine($root, 'manifest.sha256')
if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($manifest)) {
    throw 'V76.2.4.1 package-root/manifest resolution failed'
}
# V76.2.4.1 VALIDATOR PATH FIX: derive package root only from this script location.
$root = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..')).Trim()
$manifest = [IO.Path]::Combine($root, 'manifest.sha256')
if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($manifest)) {
    throw 'V76.2.4.1 package-root/manifest resolution failed'
}
if(-not(Test-Path -LiteralPath $manifest)){throw 'manifest.sha256 ausente'}
$entries=Get-Content -LiteralPath $manifest | Where-Object { $_ -match '\S' }
foreach($line in $entries){
    if($line -notmatch '^([0-9a-f]{64}) \*(.+)$'){throw "Manifest line invalida: $line"}
    $expected=$Matches[1]; $rel=$Matches[2]
    $path=Join-Path $PackageRoot ($rel.Replace('/','\'))
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Manifest target ausente: $rel"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $expected){throw "Hash mismatch: $rel expected=$expected actual=$actual"}
}
$psFiles=Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -Filter '*.ps1' -File
foreach($file in $psFiles){
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count -ne 0){throw "PowerShell parse failed: $($file.Name): $($errors[0].Message)"}
    $text=[IO.File]::ReadAllText($file.FullName)
    if($text -match '(?im)^\s*\$(host|error|input|matches|args|pwd|home|pid|psversiontable)\s*='){
        throw "Read-only/automatic variable assignment detectado: $($file.Name): $($Matches[1])"
    }
}
$helper=Join-Path $PackageRoot 'payload\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestSamplerV7624.cs'
$text=[IO.File]::ReadAllText($helper)
foreach($contract in @('NormalizeGuestBinkIntegerSamplerV7624(','SHARPEMU_BINK_INTEGER_NEAREST','[BINK-GUEST][V76.2.4][YUV-SAMPLER]','host_mag=nearest host_min=nearest host_mip=nearest')){
    if($text.IndexOf($contract,[StringComparison]::Ordinal) -lt 0){throw "Helper contract ausente: $contract"}
}
Write-Host "[$tag] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed; integer YUV sampler contracts passed)."
