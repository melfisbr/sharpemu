param()
. (Join-Path $PSScriptRoot 'common.ps1')

$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)) {
    throw "$script:Tag manifest missing"
}

$entries=@(
    Get-Content -LiteralPath $manifest |
        Where-Object { $_ -and (-not $_.StartsWith('#')) }
)

foreach($line in $entries) {
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') {
        throw "$script:Tag malformed manifest: $line"
    }
    $expected=$matches[1].ToUpperInvariant()
    $path=Join-Path $script:PackageRoot $matches[2].Replace('/','\')
    if(-not(Test-Path -LiteralPath $path)) {
        throw "$script:Tag manifest file missing: $path"
    }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if($actual -ne $expected) {
        throw "$script:Tag manifest mismatch: $path"
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
    throw "$script:Tag PowerShell parse failed: $($parseFailures -join ' | ')"
}

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

Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed; 1 bounded HostMovieBridge transform)."
