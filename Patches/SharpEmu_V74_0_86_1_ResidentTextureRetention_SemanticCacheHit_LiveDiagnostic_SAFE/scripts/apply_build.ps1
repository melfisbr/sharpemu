param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$a=$s.Agc;$p=$s.Presenter;$nl=if($a.Contains("`r`n")){"`r`n"}else{"`n"};$backup=$null
$marker='SHARPEMU_V74_0_86_1_RESIDENT_TEXTURE_RETENTION_SEMANTIC_CACHE_HIT'
if(-not($a.Contains($marker) -and $p.Contains($marker))){
 $backup=New-Backup
 try{
   # 1) Keep large standalone Vulkan textures resident much longer on the measured 16GB GPU.
   $budget=Get-StaticFieldSegment $p 'V7408StandaloneTextureCacheBudgetBytes'
   if($null -eq $budget){throw "$script:Tag standalone texture budget field vanished."}
   if(-not $budget.Text.Contains('3072')){
     $rep=[regex]::Replace($budget.Text,'("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB",\s*)768','${1}3072',1)
     if($rep -eq $budget.Text){throw "$script:Tag standalone texture budget default anchor divergiu."}
     $p=$p.Remove($budget.Start,$budget.Length).Insert($budget.Start,$rep)
   }
   $budgetAnchor='        // SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET'
   $bp=$p.IndexOf($budgetAnchor,[System.StringComparison]::Ordinal)
   if($bp -lt 0){throw "$script:Tag presenter budget comment anchor missing."}
   if(-not $p.Contains($marker)){
     $p=$p.Insert($bp,"        // $marker`r`n        // 3 GiB resident working set; env override can restore 768 MiB.`r`n")
   }

   # 2) Extend the large CPU snapshot bridge only long enough to cover slow frames.
   $ttl=Get-StaticFieldSegment $a '_v74016LargeSnapshotReuseTtlMs'
   if($null -eq $ttl){throw "$script:Tag large snapshot TTL field vanished."}
   if(-not($ttl.Text -match ':\s*10000L\s*;')){
     $rep=[regex]::Replace($ttl.Text,':\s*2000L\s*;',': 10000L;',1)
     if($rep -eq $ttl.Text){throw "$script:Tag large snapshot TTL default anchor divergiu."}
     $a=$a.Remove($ttl.Start,$ttl.Length).Insert($ttl.Start,$rep)
   }

   # 3) Once the presenter reports the exact/sampler-compatible texture cached,
   # drop the producer-side CPU snapshots immediately. This attacks the 320MB
   # bridge retention without changing the Vulkan texture contents.
   if(-not $a.Contains('_residentCpuBridgeReleaseV74086')){
     $fieldAnchor='    private static int _v74064LargeArraySnapshotEvictionTraceCount;'
     $fp=$a.IndexOf($fieldAnchor,[System.StringComparison]::Ordinal)
     if($fp -lt 0){throw "$script:Tag array cache trace field anchor missing."}
     $fe=$a.IndexOf($nl,$fp,[System.StringComparison]::Ordinal);if($fe -lt 0){throw "$script:Tag array cache trace field EOL missing."}
     $insert=$fe+$nl.Length
     $helper=@"

    // $marker
    private static readonly bool _residentCpuBridgeReleaseV74086 =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE"),
            "0",
            StringComparison.Ordinal);
    private static long _v74086ResidentBridgeReleaseCount;
    private static long _v74086ResidentBridgeReleaseBytes;

    private static void ReleaseResidentCpuBridgeSnapshotsV74086(ulong address)
    {
        if (!_residentCpuBridgeReleaseV74086 || address == 0)
        {
            return;
        }

        long releasedBytes = 0;
        var textureEntries = 0;
        var arrayEntries = 0;

        if (!_v7405LargeTextureSnapshotCache.IsEmpty)
        {
            foreach (var entry in _v7405LargeTextureSnapshotCache.ToArray())
            {
                if (entry.Key.Address != address)
                {
                    continue;
                }

                if (_v7405LargeTextureSnapshotCache.TryRemove(entry.Key, out var removed))
                {
                    releasedBytes += removed.Data.LongLength;
                    textureEntries++;
                }
            }
        }

        lock (_v74015LargeArraySnapshotGate)
        {
            if (_v74064LargeArraySnapshotCache.Count != 0)
            {
                var keys = _v74064LargeArraySnapshotCache.Keys
                    .Where(key => key.Address == address)
                    .ToArray();
                foreach (var key in keys)
                {
                    if (_v74064LargeArraySnapshotCache.TryGetValue(key, out var cached) &&
                        _v74064LargeArraySnapshotCache.Remove(key))
                    {
                        releasedBytes += cached.Data.LongLength;
                        arrayEntries++;
                    }
                }
            }
        }

        if (releasedBytes == 0)
        {
            return;
        }

        var count = Interlocked.Increment(ref _v74086ResidentBridgeReleaseCount);
        var total = Interlocked.Add(ref _v74086ResidentBridgeReleaseBytes, releasedBytes);
        if (count <= 128 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.86.1][CPU_BRIDGE_RELEASE] count={count} " +
                $"addr=0x{address:X16} texture_entries={textureEntries} " +
                $"array_entries={arrayEntries} released_mb={releasedBytes / (1024 * 1024)} " +
                $"total_released_mb={total / (1024 * 1024)}");
        }
    }
"@ -replace "`n",$nl
     $a=$a.Insert($insert,$helper)
   }

   $tex=Get-MethodSegment $a 'TryCreateGuestDrawTexture'
   if($null -eq $tex){throw "$script:Tag texture factory vanished."}
   $tm=$tex.Text
   if(-not $tm.Contains('ReleaseResidentCpuBridgeSnapshotsV74086(descriptor.Address)')){
     $query=$tm.IndexOf('GuestGpu.Current.IsTextureContentCached(',[System.StringComparison]::Ordinal)
     if($query -lt 0){throw "$script:Tag texture content cache query missing."}

     # V86.1: locate the IF that semantically owns the cache query instead of
     # depending on the first statement/formatting of its body. V85 may add
     # statements before NoteSampledAddress, which made the V86 text anchor fail.
     $ifMatches=[regex]::Matches($tm,'(?m)^\s*if\s*\(')
     $ifStart=-1
     foreach($m in $ifMatches){if($m.Index -le $query){$ifStart=$m.Index}else{break}}
     if($ifStart -lt 0){throw "$script:Tag semantic cache-hit owning if not found."}
     $paren=$tm.IndexOf('(',$ifStart,[System.StringComparison]::Ordinal)
     if($paren -lt 0 -or $paren -gt $query){throw "$script:Tag semantic cache-hit condition open paren invalid."}
     $depth=0;$closeParen=-1
     for($i=$paren;$i -lt $tm.Length;$i++){
       $ch=$tm[$i]
       if($ch -eq '('){$depth++}
       elseif($ch -eq ')'){$depth--;if($depth -eq 0){$closeParen=$i;break}}
     }
     if($closeParen -lt $query){throw "$script:Tag semantic cache-hit condition does not enclose cache query."}
     $bodyOpen=$tm.IndexOf('{',$closeParen,[System.StringComparison]::Ordinal)
     if($bodyOpen -lt 0){throw "$script:Tag semantic cache-hit body brace missing."}
     $probeLen=[Math]::Min(1800,$tm.Length-$bodyOpen)
     $bodyProbe=$tm.Substring($bodyOpen,$probeLen)
     if(-not $bodyProbe.Contains('NoteSampledAddress(descriptor.Address, descriptor.Format, descriptor.NumberType)') -or
        -not $bodyProbe.Contains('texture = new GuestDrawTexture(')){
       throw "$script:Tag semantic cache-hit body contract diverged; source not modified."
     }
     $insertion=$nl+'            // SHARPEMU_V74_0_86_1_CACHE_HIT_BRIDGE_RELEASE'+$nl+'            if (_residentCpuBridgeReleaseV74086 &&'+$nl+'                physicalSourceByteCount >= 8UL * 1024UL * 1024UL)'+$nl+'            {'+$nl+'                ReleaseResidentCpuBridgeSnapshotsV74086(descriptor.Address);'+$nl+'            }'
     $tm=$tm.Insert($bodyOpen+1,$insertion)
     $a=$a.Remove($tex.Start,$tex.Length).Insert($tex.Start,$tm)
   }

   if(-not $a.Contains($marker)){throw "$script:Tag AGC V86 marker missing after transform."}
   if(-not $p.Contains($marker)){throw "$script:Tag Presenter V86 marker missing after transform."}
   if((Get-Count $a 'SHARPEMU_V74_0_86_1_CACHE_HIT_BRIDGE_RELEASE') -ne 1){throw "$script:Tag semantic cache-hit insertion marker count invalid."}
   if((Get-Count $a 'ReleaseResidentCpuBridgeSnapshotsV74086\(descriptor\.Address\)') -ne 1){throw "$script:Tag resident bridge release call count invalid."}
   $budgetAfter=Get-StaticFieldSegment $p 'V7408StandaloneTextureCacheBudgetBytes'
   $ttlAfter=Get-StaticFieldSegment $a '_v74016LargeSnapshotReuseTtlMs'
   if(-not($budgetAfter.Text -match 'SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB[\s\S]*?3072')){throw "$script:Tag 3072 MiB texture cache default not installed."}
   if(-not($ttlAfter.Text -match ':\s*10000L\s*;')){throw "$script:Tag 10s large snapshot TTL not installed."}
   if(-not($p.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -and $p.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'))){throw "$script:Tag V81.2 Vulkan boundaries lost."}
   if(-not $a.Contains('SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')){throw "$script:Tag V85 aggressive base lost."}

   Write-Utf8NoBom $script:AgcPath $a
   Write-Utf8NoBom $script:PresenterPath $p
   Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
   Write-Host "$script:Tag standalone_texture_cache_default_mb=3072 env_override_preserved=True"
   Write-Host "$script:Tag large_texture_snapshot_default_ttl_ms=10000 env_override_preserved=True"
   Write-Host "$script:Tag resident_cpu_bridge_release=default-on semantic_cache_hit=True env_0_restores_retention"
   Write-Host "$script:Tag v85_aggressive_pm4_preserved=True"
   Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True"
   Write-Host "$script:Tag Backup=$backup"
   Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
   Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
 }catch{if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup};throw}
}else{Write-Host "$script:Tag State=AlreadyApplied"}
$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_86_1_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow};throw "$script:Tag BUILD FAILED. Log=$buildLog"}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
