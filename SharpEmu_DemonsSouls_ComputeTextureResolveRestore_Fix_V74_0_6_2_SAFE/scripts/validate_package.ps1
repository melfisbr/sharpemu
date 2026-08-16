Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$packageRoot=[System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))

$manifest=[System.IO.Path]::Combine(
    $packageRoot,
    "SHA256SUMS.txt")

if(-not [System.IO.File]::Exists($manifest)){
    throw "[V74.0.6.2] SHA256SUMS.txt missing."
}

$entries=@(
    Get-Content -LiteralPath $manifest |
    Where-Object{-not [string]::IsNullOrWhiteSpace($_)}
)

foreach($entry in $entries){
    if($entry-notmatch '^([0-9A-Fa-f]{64})\s{2}(.+)$'){
        throw "[V74.0.6.2] Invalid manifest line: $entry"
    }

    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2]
    $path=[System.IO.Path]::Combine(
        $packageRoot,
        $relative)

    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.6.2] Missing package file: $relative"
    }

    $actual=(
        Get-FileHash -LiteralPath $path -Algorithm SHA256
    ).Hash.ToUpperInvariant()

    if($actual-ne$expected){
        throw "[V74.0.6.2] Hash mismatch: $relative"
    }
}

$scripts=@(
    Get-ChildItem -LiteralPath (
        [System.IO.Path]::Combine($packageRoot,"scripts")) `
        -Filter "*.ps1" -File
)

foreach($script in $scripts){
    $tokens=$null
    $errors=$null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$tokens,
        [ref]$errors)

    if(@($errors).Count-gt 0){
        $message=(
            @($errors) |
            ForEach-Object{$_.Message}
        ) -join "; "

        throw "[V74.0.6.2] PowerShell parse error in $($script.Name): $message"
    }
}

$audit=[System.IO.Path]::Combine(
    $packageRoot,
    "audit",
    "EBOOT_IMPORT_AUDIT.csv")

if([System.IO.File]::Exists($audit)){
    $rows=@(Import-Csv -LiteralPath $audit)

    if($rows.Count-ne 1173){
        throw "[V74.0.6.2] Eboot audit row count=$($rows.Count); expected 1173."
    }
}

Write-Host "[V74.0.6.2] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; $($scripts.Count) PowerShell scripts parsed; consolidated eboot audit preserved)."
