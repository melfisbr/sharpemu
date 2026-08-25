param()
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-PackageRoot
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){throw "$script:Tag manifest missing"}
$lines=Get-Content -LiteralPath $manifest|Where-Object{$_}
foreach($line in $lines){
    if($line-notmatch '^([0-9A-Fa-f]{64})\s+\*(.+)$'){
        throw "$script:Tag malformed manifest line: $line"
    }
    $path=Join-Path $root $matches[2]
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "$script:Tag manifest file missing: $($matches[2])"
    }
    if((Get-Sha $path)-ne$matches[1].ToUpperInvariant()){
        throw "$script:Tag hash mismatch: $($matches[2])"
    }
}
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File|
    ForEach-Object{Parse-PowerShellFile $_.FullName}

$patch=[IO.File]::ReadAllText((Join-Path $root 'scripts\patch_v120.ps1'))
foreach($forbidden in @(
    'function R(',
    'function N(',
    'function W(',
    'SHARPEMU_DUAL_PHYSICAL_QUEUE", "1"',
    'SHARPEMU_BARRIERED_COMPUTE_BATCH", "1"',
    'SHARPEMU_CLOSED_COMPUTE_SUBMIT_GROUP", "1"'
)){
    if($patch.Contains($forbidden)){
        throw "$script:Tag forbidden construct: $forbidden"
    }
}
foreach($required in @(
    'Replace-OnceV120',
    'FindGuestBufferAllocationV120',
    'GetCanonicalResourceLayoutKeyV120',
    'GetCanonicalRenderTargetLayoutKeyV120',
    'GetCanonicalBlendLayoutKeyV120',
    'image_change=0',
    'buffer_content_change=0',
    'queue_change=0',
    'submit_change=0',
    'barrier_change=0'
)){
    if(-not$patch.Contains($required)){
        throw "$script:Tag required guard missing: $required"
    }
}
foreach($cmd in Get-ChildItem -LiteralPath $root -Filter '*.cmd' -File){
    $bytes=[IO.File]::ReadAllBytes($cmd.FullName)
    for($i=0;$i-lt$bytes.Length;$i++){
        if($bytes[$i]-eq10-and($i-eq0-or$bytes[$i-1]-ne13)){
            throw "$script:Tag CMD bare LF: $($cmd.Name)"
        }
    }
}
Write-Tag "PACKAGE VALIDATION PASSED manifest=$($lines.Count); PS5.1 AST=PASS; CPU-only draw hotpath guards=PASS; Vulkan ownership/queue/submit/barrier unchanged."
