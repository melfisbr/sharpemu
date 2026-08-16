$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$packageRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifestPath = [System.IO.Path]::Combine($packageRoot, "SHA256SUMS.txt")
if (-not [System.IO.File]::Exists($manifestPath)) { throw "[V74.0.23] SHA256SUMS.txt missing." }
$manifestLines = @([System.IO.File]::ReadAllLines($manifestPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$manifestFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($manifestLine in $manifestLines) {
    if ($manifestLine -notmatch '^([0-9A-Fa-f]{64})\s+\*(.+)$') { throw "[V74.0.23] Invalid manifest line: $manifestLine" }
    $expectedHash = $Matches[1].ToUpperInvariant()
    $relativePath = $Matches[2].Replace('/', '\')
    $absolutePath = [System.IO.Path]::Combine($packageRoot, $relativePath)
    if (-not [System.IO.File]::Exists($absolutePath)) { throw "[V74.0.23] Manifest file missing: $relativePath" }
    $actualHash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) { throw "[V74.0.23] SHA mismatch: $relativePath" }
    [void]$manifestFiles.Add($relativePath)
}
$actualFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object { $_.FullName.Substring($packageRoot.Length + 1) } | Where-Object { $_ -ne 'SHA256SUMS.txt' })
foreach ($relativePath in $actualFiles) {
    if (-not $manifestFiles.Contains($relativePath)) { throw "[V74.0.23] File is not covered by manifest: $relativePath" }
}
if ($manifestFiles.Count -ne $actualFiles.Count) { throw "[V74.0.23] Manifest coverage mismatch: manifest=$($manifestFiles.Count) actual=$($actualFiles.Count)" }
$parseFailures = New-Object 'System.Collections.Generic.List[string]'
foreach ($scriptFile in @(Get-ChildItem -LiteralPath $packageRoot -Recurse -Filter '*.ps1' -File)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { $parseFailures.Add("$($scriptFile.Name) :: $($parseErrors[0].Message)") }
}
if ($parseFailures.Count -gt 0) { throw "[V74.0.23] PowerShell parse failed: $($parseFailures -join '; ')" }
$reservedNames = 'Host|Args|PID|PSVersionTable|PSScriptRoot|PSCommandPath|MyInvocation|Error|Home|Input|Matches|LastExitCode|StackTrace|This|PSItem|_|NestedPromptLevel'
foreach ($scriptFile in @(Get-ChildItem -LiteralPath $packageRoot -Recurse -Filter '*.ps1' -File)) {
    $scriptText = [System.IO.File]::ReadAllText($scriptFile.FullName)
    if ($scriptText -match "(?im)^\s*\$(?:$reservedNames)\s*=") { throw "[V74.0.23] Reserved automatic variable assignment detected in $($scriptFile.Name): $($Matches[0].Trim())" }
}
foreach ($cmdFile in @(Get-ChildItem -LiteralPath $packageRoot -Filter '*.cmd' -File)) {
    $cmdText = [System.IO.File]::ReadAllText($cmdFile.FullName)
    if ($cmdText -match 'scripts\\([^"\r\n]+\.ps1)') {
        $targetPath = [System.IO.Path]::Combine($packageRoot, 'scripts', $Matches[1])
        if (-not [System.IO.File]::Exists($targetPath)) { throw "[V74.0.23] CMD target missing: $($cmdFile.Name) -> $($Matches[1])" }
    }
    else { throw "[V74.0.23] CMD has no PowerShell target: $($cmdFile.Name)" }
}
Write-Host "[V74.0.23] PACKAGE VALIDATION PASSED ($($manifestFiles.Count) hashed files; PowerShell AST parsed; CMD targets verified)."
