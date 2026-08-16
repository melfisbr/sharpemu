Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Resolve-RepoRoot([string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Get-Location).Path }
    return (Resolve-Path $RepositoryRoot).Path
}
function Get-Sha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Parse-PowerShellFile([string]$Path) {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell parse failed: $Path :: $($errors[0].Message)" }
}
