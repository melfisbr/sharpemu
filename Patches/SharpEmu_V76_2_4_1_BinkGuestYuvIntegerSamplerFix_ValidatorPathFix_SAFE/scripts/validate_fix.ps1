$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifest = [IO.Path]::Combine($packageRoot, 'manifest.sha256')
if (-not [IO.File]::Exists($manifest)) { throw "manifest.sha256 ausente: $manifest" }

$bad = New-Object System.Collections.Generic.List[string]
foreach ($line in [IO.File]::ReadAllLines($manifest)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') { throw "linha invalida no manifest: $line" }
    $expected = $Matches[1].ToLowerInvariant()
    $rel = $Matches[2]
    $path = Join-Path -Path $packageRoot -ChildPath $rel
    if (-not [IO.File]::Exists($path)) { $bad.Add("AUSENTE $rel"); continue }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { $bad.Add("HASH $rel expected=$expected actual=$actual") }
}
if ($bad.Count -gt 0) { throw ("VALIDATION FAILED:`n" + ($bad -join "`n")) }

# Parse all PowerShell scripts in this overlay.
Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed: $($_.FullName): $($errors[0].Message)"
    }
}

Write-Host '[V76.2.4.1-VALIDATOR-PATH-FIX] PACKAGE VALIDATION PASSED.' -ForegroundColor Green
