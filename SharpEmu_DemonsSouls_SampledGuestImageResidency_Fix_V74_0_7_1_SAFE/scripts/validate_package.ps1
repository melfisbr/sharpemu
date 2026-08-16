Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$packageRoot=[System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))

$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){
    throw "[V74.0.7.1] SHA256SUMS.txt missing."
}

$entries=@(
    Get-Content -LiteralPath $manifest |
    Where-Object{-not [string]::IsNullOrWhiteSpace($_)}
)

foreach($entry in $entries){
    if($entry-notmatch '^([0-9A-Fa-f]{64})\s{2}(.+)$'){
        throw "[V74.0.7.1] Invalid manifest line: $entry"
    }

    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2]
    $path=[System.IO.Path]::Combine($packageRoot,$relative)

    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.7.1] Missing package file: $relative"
    }

    $actual=(
        Get-FileHash -LiteralPath $path -Algorithm SHA256
    ).Hash.ToUpperInvariant()

    if($actual-ne$expected){
        throw "[V74.0.7.1] Hash mismatch: $relative"
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

        throw "[V74.0.7.1] PowerShell parse error in $($script.Name): $message"
    }
}

$payload=[System.IO.Path]::Combine(
    $packageRoot,
    "payload",
    "VulkanVideoPresenter.cs")

$payloadSha=(
    Get-FileHash -LiteralPath $payload -Algorithm SHA256
).Hash.ToUpperInvariant()

if($payloadSha-ne"1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28"){
    throw "[V74.0.7.1] Payload SHA mismatch: $payloadSha"
}

$payloadText=[System.IO.File]::ReadAllText($payload)

foreach($marker in @(
    "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE",
    "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET",
    "SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE",
    "SHARPEMU_V74_0_7_1_INVALIDATE_API_REPAIR"
)){
    if(-not $payloadText.Contains($marker)){
        throw "[V74.0.7.1] Payload marker missing: $marker"
    }
}

$audit=[System.IO.Path]::Combine(
    $packageRoot,
    "audit",
    "EBOOT_IMPORT_AUDIT.csv")

if([System.IO.File]::Exists($audit)){
    $rows=@(Import-Csv -LiteralPath $audit)
    if($rows.Count-ne 1173){
        throw "[V74.0.7.1] Eboot audit row count=$($rows.Count); expected 1173."
    }
}

Write-Host "[V74.0.7.1] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; $($scripts.Count) PowerShell scripts parsed; payload_sha=1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28)."
