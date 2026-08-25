param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$bootstrapTag='[V74.0.118.7.6.3.13.1-DS-RAD-NIHAV-HYBRID-PARSERFIX]'
$packageRoot=Split-Path -Parent $PSScriptRoot
$manifest=Join-Path $packageRoot 'manifest.sha256'

if(-not(Test-Path -LiteralPath $manifest)) {
    throw "$bootstrapTag manifest missing"
}

$entries=@(
    Get-Content -LiteralPath $manifest |
        Where-Object { $_ -and (-not $_.StartsWith('#')) }
)

foreach($line in $entries) {
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') {
        throw "$bootstrapTag malformed manifest: $line"
    }
    $expected=$matches[1].ToUpperInvariant()
    $itemPath=Join-Path $packageRoot $matches[2].Replace('/','\')
    if(-not(Test-Path -LiteralPath $itemPath)) {
        throw "$bootstrapTag manifest file missing: $itemPath"
    }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $itemPath).Hash.ToUpperInvariant()
    if($actual -ne $expected) {
        throw "$bootstrapTag manifest mismatch: $itemPath"
    }
}

$parseFailures=@()
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens=$null
    $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors)
    if(@($parseErrors).Count -ne 0) {
        $parseFailures +=
            "$($file.Name):$(($parseErrors | ForEach-Object {$_.Message}) -join '; ')"
    }
}
if($parseFailures.Count -ne 0) {
    throw "$bootstrapTag PowerShell parse failed: $($parseFailures -join ' | ')"
}

# common.ps1 is loaded only after all package PowerShell parsed successfully.
. (Join-Path $PSScriptRoot 'common.ps1')

$old=Get-OldHunk
$new=Get-NewHunk
if([string]::IsNullOrWhiteSpace($old) -or
   [string]::IsNullOrWhiteSpace($new) -or
   $old -eq $new) {
    throw "$script:Tag invalid HostMovieBridge transform payload"
}

foreach($marker in @(
    'SHARPEMU_V74_0_118_7_6_3_13_RAD_NIHAV_HYBRID_RESTORE',
    '[V74.0.118.7.6.3.13][RAD_NIHAV_HYBRID_ROUTE]',
    'explicit_opt_in=True',
    'historical_baseline=V74.0.88.6.2')) {
    if(-not$new.Contains($marker)) {
        throw "$script:Tag transform marker missing: $marker"
    }
}

# Transform-level self-test independent of repository state.
$oldShape=Get-HunkState $old
if($oldShape.State -ne 'original' -or
   $oldShape.OldCount -ne 1 -or
   $oldShape.NewCount -ne 0) {
    throw "$script:Tag transform selftest old-shape failed state=$($oldShape.State) old=$($oldShape.OldCount) new=$($oldShape.NewCount)"
}

$newShape=Get-HunkState $new
if($newShape.State -ne 'patched' -or
   $newShape.OldCount -ne 0 -or
   $newShape.NewCount -ne 1) {
    throw "$script:Tag transform selftest new-shape failed state=$($newShape.State) old=$($newShape.OldCount) new=$($newShape.NewCount)"
}

Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed before common load; transform selftests passed; 1 bounded HostMovieBridge transform)."
