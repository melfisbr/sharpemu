. (Join-Path $PSScriptRoot 'common.ps1')

param(
    [Parameter(Mandatory=$true)][string[]]$LogPaths,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

$lines=New-Object System.Collections.Generic.List[string]
foreach($path in $LogPaths){
    if(Test-Path -LiteralPath $path -PathType Leaf){
        foreach($line in [IO.File]::ReadAllLines($path)){
            $lines.Add($line)
        }
    }
}

function Get-IntField {
    param([string]$Line,[string]$Name)
    $m=[regex]::Match($Line,'(?:^|\s)'+[regex]::Escape($Name)+'=(\d+)')
    if($m.Success){return [long]$m.Groups[1].Value}
    return $null
}

function Get-DecimalCommaField {
    param([string]$Line,[string]$Name)
    $m=[regex]::Match(
        $Line,
        '(?:^|\s)'+[regex]::Escape($Name)+'=(\d+)(?:,(\d+))?')
    if(!$m.Success){return $null}
    $whole=[double]$m.Groups[1].Value
    if($m.Groups[2].Success){
        $fraction=$m.Groups[2].Value
        return [double]::Parse(
            ($m.Groups[1].Value+'.'+$fraction),
            [Globalization.CultureInfo]::InvariantCulture)
    }
    return $whole
}

$mem=New-Object System.Collections.Generic.List[object]
$arrayOwners=New-Object System.Collections.Generic.List[object]
$slowWaits=New-Object System.Collections.Generic.List[double]
$dedicatedWaits=New-Object System.Collections.Generic.List[double]

$arrayEvicts=0
$capacityYields=0
$capacityPending24=0
$capacityQueuedMax=0
$hardCapProbes=0
$hardCapNoProgress=0
$producerCompletedSlow=0
$dlssActiveLines=0
$dlssDispatchMax=0
$dlssFailuresMax=0
$ttl120Owners=0
$ttlOtherOwners=0
$normalExit=$false

foreach($line in $lines){
    if($line.Contains('[V74.0.8.1][MEM]')){
        $mem.Add([pscustomobject]@{
            Alloc2s=Get-IntField $line 'alloc2s_mb'
            Heap=Get-IntField $line 'heap_mb'
            Frag=Get-IntField $line 'frag_mb'
            Working=Get-IntField $line 'working_mb'
            Private=Get-IntField $line 'private_mb'
            GuestImage=Get-IntField $line 'guest_image_total_mb'
            TexCache=Get-IntField $line 'tex_cache_mb'
            TexDeferred=Get-IntField $line 'tex_deferred_mb'
        })
    }

    if($line.Contains('[V74.0.64][ARRAY_CACHE_OWNER]')){
        $bytes=Get-IntField $line 'bytes'
        $ttl=Get-IntField $line 'ttl_ms'
        $addrMatch=[regex]::Match($line,'addr=(0x[0-9A-Fa-f]+)')
        $addr=if($addrMatch.Success){$addrMatch.Groups[1].Value}else{'unknown'}
        $arrayOwners.Add([pscustomobject]@{
            Bytes=$bytes
            Ttl=$ttl
            Addr=$addr
        })
        if($ttl-eq 120000){$ttl120Owners++}else{$ttlOtherOwners++}
    }

    if($line.Contains('[V74.0.64][ARRAY_CACHE_EVICT]')){$arrayEvicts++}

    if($line.Contains('[V74.0.27][SLOW_WAIT_PRODUCER]')){
        $wait=Get-DecimalCommaField $line 'waited_ms'
        if($null-ne $wait){$slowWaits.Add($wait)}
        if($line.Contains('producer_state=completed') -and
           $line.Contains('producer_completed_after_wait=1')){
            $producerCompletedSlow++
        }
    }

    if($line.Contains('[V74.0.71][DEDICATED_WAIT_DRAIN]')){
        $wait=Get-DecimalCommaField $line 'gate_wait_ms'
        if($null-ne $wait){$dedicatedWaits.Add($wait)}
    }

    if($line.Contains('[V74.0.33][SUBMISSION_CAPACITY_YIELD]')){
        $capacityYields++
        $pending=Get-IntField $line 'pending'
        $queued=Get-IntField $line 'queued_work'
        if($pending-eq 24){$capacityPending24++}
        if($null-ne $queued -and $queued-gt $capacityQueuedMax){
            $capacityQueuedMax=$queued
        }
    }

    if($line.Contains('[V74.0.46][INLINE_HARD_CAP_FENCE_PROBE]')){
        $hardCapProbes++
        $before=Get-IntField $line 'pending_before'
        $after=Get-IntField $line 'pending_after'
        if($null-ne $before -and $null-ne $after -and $after-ge $before){
            $hardCapNoProgress++
        }
    }

    if($line.Contains('[V74.0.67][UPSCALER][RUNTIME]') -and
       $line.Contains('selected=dlss') -and
       $line.Contains('state=active')){
        $dlssActiveLines++
        $dispatch=Get-IntField $line 'dlss_dispatches'
        $fail=Get-IntField $line 'dispatch_failures'
        if($null-ne $dispatch -and $dispatch-gt $dlssDispatchMax){
            $dlssDispatchMax=$dispatch
        }
        if($null-ne $fail -and $fail-gt $dlssFailuresMax){
            $dlssFailuresMax=$fail
        }
    }

    if($line.Contains('Process exited with code 0 (OK).')){$normalExit=$true}
}

function Add-Stats {
    param(
        [System.Collections.Generic.List[string]]$Result,
        [string]$Name,
        [object[]]$Values
    )
    $filtered=@($Values | Where-Object {$null-ne $_})
    if($filtered.Count-eq 0){
        $Result.Add("$Name count=0")
        return
    }
    $measure=$filtered | Measure-Object -Minimum -Maximum -Average -Sum
    $Result.Add(
        ('{0} count={1} min={2:N1} max={3:N1} avg={4:N1} sum={5:N1}' -f
            $Name,$filtered.Count,$measure.Minimum,$measure.Maximum,
            $measure.Average,$measure.Sum))
}

$result=New-Object System.Collections.Generic.List[string]
$result.Add('[V74.0.67.2.16] RUNTIME ANALYSIS START')
$result.Add("log_lines=$($lines.Count)")
$result.Add("normal_exit=$($normalExit.ToString().ToLowerInvariant())")
$result.Add("dlss_active_lines=$dlssActiveLines")
$result.Add("dlss_dispatch_max=$dlssDispatchMax")
$result.Add("dlss_dispatch_failures_max=$dlssFailuresMax")

Add-Stats -Result $result -Name 'mem_alloc2s_mb' -Values @($mem | ForEach-Object {$_.Alloc2s})
Add-Stats -Result $result -Name 'mem_heap_mb' -Values @($mem | ForEach-Object {$_.Heap})
Add-Stats -Result $result -Name 'mem_frag_mb' -Values @($mem | ForEach-Object {$_.Frag})
Add-Stats -Result $result -Name 'mem_working_mb' -Values @($mem | ForEach-Object {$_.Working})
Add-Stats -Result $result -Name 'mem_private_mb' -Values @($mem | ForEach-Object {$_.Private})
Add-Stats -Result $result -Name 'mem_guest_image_mb' -Values @($mem | ForEach-Object {$_.GuestImage})
Add-Stats -Result $result -Name 'mem_tex_cache_mb' -Values @($mem | ForEach-Object {$_.TexCache})
Add-Stats -Result $result -Name 'mem_tex_deferred_mb' -Values @($mem | ForEach-Object {$_.TexDeferred})

$arrayOwnerBytes=@($arrayOwners | ForEach-Object {$_.Bytes})
Add-Stats -Result $result -Name 'array_owner_bytes' -Values $arrayOwnerBytes
$result.Add("array_owner_count=$($arrayOwners.Count)")
$result.Add("array_evict_count=$arrayEvicts")
$result.Add("array_owner_ttl120_count=$ttl120Owners")
$result.Add("array_owner_non120_count=$ttlOtherOwners")

$ownerSumBytes=0L
foreach($entry in $arrayOwners){
    if($null-ne $entry.Bytes){$ownerSumBytes += [long]$entry.Bytes}
}
$ownerSumMb=[Math]::Round($ownerSumBytes/1MB,1)
$result.Add("array_owner_sum_mb=$ownerSumMb")

$distinct=New-Object 'System.Collections.Generic.HashSet[string]'
foreach($entry in $arrayOwners){
    $null=$distinct.Add(("$($entry.Addr):$($entry.Bytes)"))
}
$result.Add("array_owner_distinct_key_count=$($distinct.Count)")

Add-Stats -Result $result -Name 'slow_wait_ms' -Values @($slowWaits)
$result.Add("slow_wait_completed_producer_count=$producerCompletedSlow")
Add-Stats -Result $result -Name 'dedicated_gate_wait_ms' -Values @($dedicatedWaits)
$result.Add("submission_capacity_yield_count=$capacityYields")
$result.Add("submission_capacity_pending24_count=$capacityPending24")
$result.Add("submission_capacity_queued_work_max=$capacityQueuedMax")
$result.Add("hard_cap_probe_count=$hardCapProbes")
$result.Add("hard_cap_probe_no_progress_count=$hardCapNoProgress")

$allocSum=0.0
foreach($entry in $mem){
    if($null-ne $entry.Alloc2s){$allocSum += [double]$entry.Alloc2s}
}
$result.Add(('sampled_alloc2s_sum_mb={0:N1}' -f $allocSum))
if($allocSum-gt 0){
    $ratio=100.0*$ownerSumMb/$allocSum
    $result.Add(('array_owner_vs_sampled_alloc_ratio_pct={0:N2}' -f $ratio))
}

if($ttl120Owners-gt 0 -and $ttlOtherOwners-eq 0){
    $result.Add('CONCLUSION ttl120=working')
}else{
    $result.Add('CONCLUSION ttl120=not_proven_or_mixed')
}

if($arrayEvicts-gt 0 -and $distinct.Count-gt 2){
    $result.Add('CONCLUSION array_cache=capacity_churn_present')
}

if($producerCompletedSlow-gt 0){
    $result.Add('CONCLUSION waits=completed_producer_wake_latency_present')
}

if($capacityYields-gt 0 -and $capacityPending24-eq $capacityYields){
    $result.Add('CONCLUSION submissions=hard_cap_24_saturation_present')
}

if($hardCapProbes-gt 0 -and $hardCapNoProgress*100 -ge $hardCapProbes*80){
    $result.Add('CONCLUSION hard_cap_probe=mostly_no_progress')
}

$result.Add('[V74.0.67.2.16] RUNTIME ANALYSIS END')

[IO.File]::WriteAllLines(
    $OutputPath,
    $result,
    [Text.UTF8Encoding]::new($false))

Write-Host "[V74.0.67.2.16] RuntimeAnalysis=$OutputPath"
foreach($line in $result){Write-Host $line}
