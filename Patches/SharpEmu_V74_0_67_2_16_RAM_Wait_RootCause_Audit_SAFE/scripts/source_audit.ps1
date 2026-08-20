. (Join-Path $PSScriptRoot 'common.ps1')

param(
    [string]$OutputPath
)

$repo=Get-RepoRoot
$patches=Get-PatchesRoot
if([string]::IsNullOrWhiteSpace($OutputPath)){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputPath=Join-Path $patches "SharpEmu_V74_0_67_2_16_SOURCE_AUDIT_$stamp.txt"
}

$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'

foreach($path in @($agcPath,$presenterPath,$bridgePath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing required source: $path"
    }
}

$result=New-Object System.Collections.Generic.List[string]
$result.Add('[V74.0.67.2.16] SOURCE AUDIT START')
$result.Add("RepositoryRoot=$repo")

function Add-Window {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Needle,
        [int]$Before=40,
        [int]$After=120,
        [string]$Label=''
    )

    $lines=[IO.File]::ReadAllLines($Path)
    $indices=New-Object System.Collections.Generic.List[int]
    for($i=0;$i-lt $lines.Length;$i++){
        if($lines[$i].IndexOf($Needle,[StringComparison]::Ordinal)-ge 0){
            $indices.Add($i)
        }
    }

    $name=[IO.Path]::GetFileName($Path)
    $result.Add("WINDOW label=$Label file=$name needle=$Needle count=$($indices.Count)")
    foreach($index in $indices){
        $start=[Math]::Max(0,$index-$Before)
        $end=[Math]::Min($lines.Length-1,$index+$After)
        $result.Add("----- BEGIN $Label $name line=$($index+1) range=$($start+1)-$($end+1) -----")
        for($j=$start;$j-le $end;$j++){
            $result.Add(('{0:D6}: {1}' -f ($j+1),$lines[$j]))
        }
        $result.Add("----- END $Label -----")
    }
}

function Add-RegexHits {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $lines=[IO.File]::ReadAllLines($Path)
    $count=0
    for($i=0;$i-lt $lines.Length;$i++){
        if([regex]::IsMatch($lines[$i],$Pattern)){
            $count++
            $result.Add(
                ("ALLOC_SITE label={0} file={1} line={2} text={3}" -f
                    $Label,[IO.Path]::GetFileName($Path),($i+1),$lines[$i].Trim()))
        }
    }
    $result.Add("ALLOC_SITE_COUNT label=$Label count=$count")
}

# Exact accumulated large-array cache implementation and the surrounding call sites.
Add-Window -Path $agcPath -Needle 'TryGetLargeArraySnapshotV74064' `
    -Before 100 -After 220 -Label 'agc-array-cache-lookup'
Add-Window -Path $agcPath -Needle 'StoreLargeArraySnapshotV74064' `
    -Before 100 -After 240 -Label 'agc-array-cache-store'
Add-Window -Path $agcPath -Needle '[V74.0.64][ARRAY_CACHE_EVICT]' `
    -Before 120 -After 180 -Label 'agc-array-cache-eviction'
Add-Window -Path $agcPath -Needle '[V74.0.64][ARRAY_CACHE_OWNER]' `
    -Before 120 -After 180 -Label 'agc-array-cache-owner'
Add-Window -Path $agcPath -Needle 'V74067215LargeArraySnapshotTtlMs' `
    -Before 50 -After 120 -Label 'agc-v215-effective-ttl'

# Exact wait / producer-completion implementation. This is the next performance
# target only if the source proves a safe wake/visibility hook.
Add-Window -Path $agcPath -Needle '[V74.0.27][SLOW_WAIT_PRODUCER]' `
    -Before 180 -After 260 -Label 'agc-slow-wait-producer'
Add-Window -Path $agcPath -Needle '[V74.0.71][DEDICATED_WAIT_DRAIN]' `
    -Before 160 -After 240 -Label 'agc-dedicated-wait-drain'
Add-Window -Path $agcPath -Needle '[V74.0.72][GATE_OWNER_WAIT_DRAIN]' `
    -Before 160 -After 240 -Label 'agc-gate-owner-wait-drain'
Add-Window -Path $agcPath -Needle 'RequestResumableDcbDrain' `
    -Before 100 -After 180 -Label 'agc-resumable-dcb-drain'
Add-Window -Path $agcPath -Needle 'PumpSubmittedQueuesV74030' `
    -Before 80 -After 160 -Label 'agc-pump-submitted-queues'

# Presenter queue saturation and memory-allocation surfaces.
Add-Window -Path $presenterPath -Needle '[V74.0.33][SUBMISSION_CAPACITY_YIELD]' `
    -Before 150 -After 220 -Label 'vk-submission-capacity-yield'
Add-Window -Path $presenterPath -Needle '[V74.0.46][INLINE_HARD_CAP_FENCE_PROBE]' `
    -Before 150 -After 220 -Label 'vk-inline-hard-cap-probe'
Add-Window -Path $presenterPath -Needle 'BeginBatchedGuestCommands' `
    -Before 80 -After 140 -Label 'vk-batch-begin'
Add-Window -Path $presenterPath -Needle 'SubmitGuestCommandBuffer' `
    -Before 120 -After 240 -Label 'vk-submit-guest-command-buffer'

# Allocation-site inventory. This intentionally does not modify runtime.
Add-RegexHits -Path $agcPath -Pattern 'new\s+byte\s*\[' -Label 'agc-new-byte-array'
Add-RegexHits -Path $agcPath -Pattern 'GC\.AllocateUninitializedArray\s*<\s*byte\s*>' -Label 'agc-gc-byte-array'
Add-RegexHits -Path $agcPath -Pattern '\.ToArray\s*\(\s*\)' -Label 'agc-toarray'
Add-RegexHits -Path $presenterPath -Pattern 'new\s+byte\s*\[' -Label 'vk-new-byte-array'
Add-RegexHits -Path $presenterPath -Pattern 'GC\.AllocateUninitializedArray\s*<\s*byte\s*>' -Label 'vk-gc-byte-array'
Add-RegexHits -Path $presenterPath -Pattern '\.ToArray\s*\(\s*\)' -Label 'vk-toarray'

# Critical state checks.
$agc=[IO.File]::ReadAllText($agcPath)
$bridge=[IO.File]::ReadAllText($bridgePath)
$result.Add("STATE v215_ttl=$($agc.Contains('V74.0.67.2.15 effective large-array TTL'))")
$result.Add("STATE v213_content_identity=$($agc.Contains('V74.0.67.2.13 large-array sparse-content reuse key'))")
$result.Add("STATE v214_dlss_command_buffer=$($bridge.Contains('V74.0.67.2.14 pre-composite command-buffer ownership'))")
$result.Add('[V74.0.67.2.16] SOURCE AUDIT END')

[IO.File]::WriteAllLines(
    $OutputPath,
    $result,
    [Text.UTF8Encoding]::new($false))

Write-Host "[V74.0.67.2.16] SourceAudit=$OutputPath"
