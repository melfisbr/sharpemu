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
        throw "[V74.0.11.1] Invalid manifest line: $entry"
    }

    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2]
    $path=[System.IO.Path]::Combine($packageRoot,$relative)

    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.11.1] Missing package file: $relative"
    }

    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual-ne$expected){
        throw "[V74.0.11.1] Hash mismatch: $relative"
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
        throw "[V74.0.11.1] PowerShell parse error in $($script.Name): $((@($errors)|ForEach-Object{$_.Message})-join '; ')"
    }
}

$native=[System.IO.Path]::Combine(
    $packageRoot,"payload","DirectExecutionBackend.NativeWorker.cs")
$nativeSha=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
if($nativeSha-ne"F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38"){
    throw "[V74.0.11.1] NativeWorker payload SHA mismatch: $nativeSha"
}

$presenter=[System.IO.Path]::Combine(
    $packageRoot,"payload","VulkanVideoPresenter.cs")
$presenterSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
if($presenterSha-ne"B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41"){
    throw "[V74.0.11.1] Presenter payload SHA mismatch: $presenterSha"
}

$presenterText=[System.IO.File]::ReadAllText($presenter)
foreach($marker in @(
    "SHARPEMU_V74_0_11_NATURAL_BINK_DESCRIPTORLESS_DIRECT_FALLBACK",
    "SHARPEMU_V74_0_11_NATURAL_BINK_RENDER_TICK_PUMP",
    "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET",
    "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE"
)){
    if(-not $presenterText.Contains($marker)){
        throw "[V74.0.11.1] Required presenter marker missing: $marker"
    }
}

$audit=[System.IO.Path]::Combine($packageRoot,"audit","EBOOT_IMPORT_AUDIT.csv")
if([System.IO.File]::Exists($audit)){
    $rows=@(Import-Csv -LiteralPath $audit)
    if($rows.Count-ne 1173){
        throw "[V74.0.11.1] Eboot audit row count=$($rows.Count); expected 1173."
    }
}

Write-Host "[V74.0.11.1] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; $($scripts.Count) PowerShell scripts parsed; presenter_payload=B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41)."

Write-Host "[V74.0.11.1] Runtime NativeWorker accepted by semantic V74.0.10 lane contract; reference_sha=F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38; observed_checkout_sha=8E0FE4E3C23860592E29A9A5B2EA5D6AE974D221098D2ABBB31474087124CFC3."
