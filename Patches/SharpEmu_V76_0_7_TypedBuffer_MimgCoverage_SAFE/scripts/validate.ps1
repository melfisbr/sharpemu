. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'manifest.sha256 ausente' }
$checked = 0
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$') { throw "Linha invalida no manifest: $line" }
    $expected = $Matches[1].ToLowerInvariant()
    $relative = $Matches[2].Replace('/', '\')
    $path = Join-Path $PackageRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo do manifest ausente: $relative" }
    $actual = Get-Sha256 $path
    if ($actual -ne $expected) { throw "Hash invalido: $relative expected=$expected actual=$actual" }
    $checked++
}
foreach ($scriptFile in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $parseIssues = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseIssues)
    if ($parseIssues -and $parseIssues.Count -gt 0) {
        throw "PowerShell parse failure em $($scriptFile.Name): $(($parseIssues | ForEach-Object {$_.Message}) -join '; ')"
    }
}
Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed)."
