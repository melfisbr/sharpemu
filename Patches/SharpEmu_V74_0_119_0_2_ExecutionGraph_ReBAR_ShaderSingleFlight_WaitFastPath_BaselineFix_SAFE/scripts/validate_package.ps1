param()
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-PackageRoot
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path $manifest)){throw "$script:Tag manifest missing"}
$lines=Get-Content $manifest|Where-Object{$_}
foreach($line in $lines){
    if($line-notmatch '^([0-9A-Fa-f]{64})\s+\*(.+)$'){throw "$script:Tag malformed manifest"}
    $p=Join-Path $root $matches[2]
    if(-not(Test-Path $p -PathType Leaf)){throw "$script:Tag missing $($matches[2])"}
    if((Get-Sha $p)-ne$matches[1].ToUpperInvariant()){throw "$script:Tag hash mismatch $($matches[2])"}
}
Get-ChildItem $root -Recurse -File -Filter '*.ps1'|ForEach-Object{Parse-PowerShell $_.FullName}
foreach($cmd in Get-ChildItem $root -File -Filter '*.cmd'){
    $b=[IO.File]::ReadAllBytes($cmd.FullName)
    for($i=0;$i-lt$b.Length;$i++){
        if($b[$i]-eq10-and($i-eq0-or$b[$i-1]-ne13)){throw "$script:Tag bare LF $($cmd.Name)"}
    }
}
$p=[IO.File]::ReadAllText((Join-Path $root 'scripts\patch_v1190.ps1'))
foreach($forbidden in @('function R(','function N(','function W(','DUAL_PHYSICAL_QUEUE", "1"','BARRIERED_COMPUTE_BATCH", "1"')){
    if($p.Contains($forbidden)){throw "$script:Tag forbidden package construct: $forbidden"}
}
foreach($required in @(
    'Replace-OnceV1190',
    'SHARPEMU_V74_0_119_0_SHADER_SINGLEFLIGHT',
    'SHARPEMU_V74_0_119_0_WAITER_EVENT_FASTPATH',
    'SHARPEMU_V74_0_119_0_RESIDENT_SHADER_REFERENCE_FASTPATH',
    'SHARPEMU_V74_0_119_0_REBAR_GLOBAL_DIRECT',
    'MemoryClassV1190',
    'queue_order_change=0',
    'submit_change=0',
    'barrier_change=0',
    'image_lifetime_change=0',
    '_rebarGlobalSupportStateV11901',
    'allocateResultV11901 != Result.Success',
    'mapResultV11901 != Result.Success'
)){
    if(-not$p.Contains($required)){throw "$script:Tag required guard missing: $required"}
}

$commonText=[IO.File]::ReadAllText((Join-Path $root 'scripts\common.ps1'))
foreach($requiredOwnerFix in @(
    'function Get-GpuWaitRegistrySource',
    '$w=[IO.File]::ReadAllText((Get-GpuWaitRegistrySource))',
    'public static bool HasLatchedSatisfiedV74100',
    'GpuWaitRegistry baseline missing'
)){
    if(-not$commonText.Contains($requiredOwnerFix)){
        throw "$script:Tag baseline-owner fix missing: $requiredOwnerFix"
    }
}
$agcBaseline=[regex]::Match(
    $commonText,
    '(?s)\$a=\[IO\.File\]::ReadAllText\(\(Get-AgcSource\)\).*?\$w=\[IO\.File\]::ReadAllText').Value
if([string]::IsNullOrEmpty($agcBaseline)){
    throw "$script:Tag unable to isolate AGC baseline block"
}
if($agcBaseline.Contains("'HasLatchedSatisfiedV74100'")){
    throw "$script:Tag wrong-owner regression: HasLatchedSatisfiedV74100 cannot be required in AgcExports.cs"
}

Write-Tag "PACKAGE VALIDATION PASSED ($($lines.Count) files; PS5.1-safe helpers; GpuWaitRegistry owner-fix; execution-graph safety guards passed)."
