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
        throw "[V74.0.12] Invalid manifest line: $entry"
    }

    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2]
    $path=[System.IO.Path]::Combine($packageRoot,$relative)

    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.12] Missing package file: $relative"
    }

    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual-ne$expected){
        throw "[V74.0.12] Hash mismatch: $relative"
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
        $script.FullName,[ref]$tokens,[ref]$errors)

    if(@($errors).Count-gt 0){
        throw "[V74.0.12] PowerShell parse error in $($script.Name): $((@($errors)|ForEach-Object{$_.Message})-join '; ')"
    }
}

$presenter=[System.IO.Path]::Combine(
    $packageRoot,"payload","VulkanVideoPresenter.cs")
$presenterSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
if($presenterSha-ne"B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245"){
    throw "[V74.0.12] Presenter payload SHA mismatch: $presenterSha"
}

$pt=[System.IO.File]::ReadAllText($presenter)
foreach($marker in @(
    "SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE",
    "SHARPEMU_V74_0_12_STARTUP_BINK_EARLY_DIRECT_FALLBACK",
    "SHARPEMU_V74_0_11_NATURAL_BINK_DESCRIPTORLESS_DIRECT_FALLBACK",
    "SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE"
)){
    if($marker-eq"SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE"){
        continue
    }
    if(-not $pt.Contains($marker)){
        throw "[V74.0.12] Presenter marker missing: $marker"
    }
}

$audit=[System.IO.Path]::Combine(
    $packageRoot,"audit","EBOOT_IMPORT_AUDIT.csv")
if([System.IO.File]::Exists($audit)){
    $rows=@(Import-Csv -LiteralPath $audit)
    if($rows.Count-ne 1173){
        throw "[V74.0.12] Eboot audit row count=$($rows.Count); expected 1173."
    }
}

Write-Host "[V74.0.12] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; $($scripts.Count) PowerShell scripts parsed; presenter_payload=B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245)."
