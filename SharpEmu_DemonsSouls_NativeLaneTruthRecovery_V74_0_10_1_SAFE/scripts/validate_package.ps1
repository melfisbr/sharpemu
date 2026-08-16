Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$packageRoot=[System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")

$entries=@(
    Get-Content -LiteralPath $manifest |
    Where-Object{-not [string]::IsNullOrWhiteSpace($_)}
)
foreach($entry in $entries){
    if($entry-notmatch '^([0-9A-Fa-f]{64})\s{2}(.+)$'){
        throw "[V74.0.10.1] Invalid manifest line: $entry"
    }
    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2]
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.10.1] Missing package file: $relative"
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual-ne$expected){
        throw "[V74.0.10.1] Hash mismatch: $relative"
    }
}

$scripts=@(
    Get-ChildItem -LiteralPath ([System.IO.Path]::Combine($packageRoot,"scripts")) `
        -Filter "*.ps1" -File
)
foreach($script in $scripts){
    $tokens=$null
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,[ref]$tokens,[ref]$errors)
    if(@($errors).Count-gt 0){
        throw "[V74.0.10.1] PowerShell parse error in $($script.Name): $((@($errors)|ForEach-Object{$_.Message})-join '; ')"
    }
}

$payload=[System.IO.Path]::Combine(
    $packageRoot,"payload","DirectExecutionBackend.NativeWorker.cs")
$sha=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToUpperInvariant()
if($sha-ne"F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38"){
    throw "[V74.0.10.1] NativeWorker payload SHA mismatch: $sha"
}

$payloadText=[System.IO.File]::ReadAllText($payload)
foreach($marker in @(
    "SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE",
    "SHARPEMU_V74_0_3_4_NO_MANAGED_INLINE_FALLBACK",
    "SHARPEMU_V73_20_4_1_DEDICATED_GUEST_NATIVE_EXECUTOR"
)){
    if(-not $payloadText.Contains($marker)){
        throw "[V74.0.10.1] Required payload marker missing: $marker"
    }
}

$audit=[System.IO.Path]::Combine($packageRoot,"audit","EBOOT_IMPORT_AUDIT.csv")
if([System.IO.File]::Exists($audit)){
    $rows=@(Import-Csv -LiteralPath $audit)
    if($rows.Count-ne 1173){
        throw "[V74.0.10.1] Eboot audit row count=$($rows.Count); expected 1173."
    }
}

Write-Host "[V74.0.10.1] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; $($scripts.Count) PowerShell scripts parsed; payload_sha=F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38)."
