param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$a=$s.Agc;$p=$s.Presenter;$nl=if($a.Contains("`r`n")){"`r`n"}else{"`n"};$backup=$null
$marker='SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR'
if(-not($a.Contains($marker) -and $p.Contains($marker))){
 $backup=New-Backup
 try{
   # 1) Keep large standalone Vulkan textures resident longer. The environment
   # override remains authoritative and can restore 768 MiB for A/B.
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
     $p=$p.Insert($bp,"        // $marker`r`n        // Presenter-owned residency + producer bridge retirement.`r`n")
   }

   # 2) Keep the exact large-snapshot bridge alive for slow frames, but retire
   # it as soon as the presenter marks the corresponding Vulkan content cached.
   $ttl=Get-StaticFieldSegment $a '_v74016LargeSnapshotReuseTtlMs'
   if($null -eq $ttl){throw "$script:Tag large snapshot TTL field vanished."}
   if(-not($ttl.Text -match ':\s*10000L\s*;')){
     $rep=[regex]::Replace($ttl.Text,':\s*2000L\s*;',': 10000L;',1)
     if($rep -eq $ttl.Text){throw "$script:Tag large snapshot TTL default anchor divergiu."}
     $a=$a.Remove($ttl.Start,$ttl.Length).Insert($ttl.Start,$rep)
   }

   # 3) Producer-side retirement helper. It only removes bridge-cache references;
   # it does not mutate GuestDrawTexture payloads already owned by an in-flight
   # work item and does not touch Vulkan resources or queue ordering.
   if(-not $a.Contains('ReleaseResidentCpuBridgeSnapshotsV740864')){
     $fieldAnchor='    private static int _v74064LargeArraySnapshotEvictionTraceCount;'
     $fp=$a.IndexOf($fieldAnchor,[System.StringComparison]::Ordinal)
     if($fp -lt 0){throw "$script:Tag array cache trace field anchor missing."}
     # V86.4: insert after the semicolon of the known field; no CRLF/LF dependency.
     $fieldSemi=$a.IndexOf(';',$fp,[System.StringComparison]::Ordinal)
     if($fieldSemi -lt $fp){throw "$script:Tag array cache trace field semicolon missing."}
     $insert=$fieldSemi+1
     $helper=@"

    // $marker
    private static readonly bool _residentCpuBridgeReleaseV740864 =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE"),
            "0",
            StringComparison.Ordinal);
    private static long _v740864ResidentBridgeReleaseCount;
    private static long _v740864ResidentBridgeReleaseBytes;

    internal static void ReleaseResidentCpuBridgeSnapshotsV740864(ulong address)
    {
        if (!_residentCpuBridgeReleaseV740864 || address == 0)
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

        var count = Interlocked.Increment(ref _v740864ResidentBridgeReleaseCount);
        var total = Interlocked.Add(ref _v740864ResidentBridgeReleaseBytes, releasedBytes);
        if (count <= 128 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.86.4][CPU_BRIDGE_RELEASE] count={count} " +
                $"addr=0x{address:X16} texture_entries={textureEntries} " +
                $"array_entries={arrayEntries} released_mb={releasedBytes / (1024 * 1024)} " +
                $"total_released_mb={total / (1024 * 1024)}");
        }
    }
"@ -replace "`n",$nl
     $a=$a.Insert($insert,$helper)
   }

   # 4) Semantic insertion point: presenter cache registration. This completely
   # avoids TryCreateGuestDrawTexture/cache-hit/NoteSampledAddress layout.
   $mark=Get-MethodSegment $p 'MarkTextureContentCached'
   if($null -eq $mark){throw "$script:Tag MarkTextureContentCached vanished."}
   $mm=$mark.Text
   if(-not $mm.Contains('ReleaseResidentCpuBridgeSnapshotsV740864(identity.Address)')){
     $anchor='_cachedTextureIdentities.TryAdd(identity, 0);'
     $ap=$mm.IndexOf($anchor,[System.StringComparison]::Ordinal)
     if($ap -lt 0){throw "$script:Tag presenter cache registration statement missing."}
     if($mm.IndexOf($anchor,$ap+1,[System.StringComparison]::Ordinal) -ge 0){throw "$script:Tag presenter cache registration statement ambiguous."}
     # V86.4: semicolon-anchored insertion. Do not depend on CRLF/LF or on the
     # location of any following statement. The anchor itself already ends in ';'.
     $semi=$ap+$anchor.Length-1
     if($semi -lt $ap -or $semi -ge $mm.Length -or $mm[$semi] -ne ';'){throw "$script:Tag presenter cache registration semicolon anchor invalid."}
     $nlP=if($mm.Contains("`r`n")){"`r`n"}else{"`n"}
     $insertAt=$semi+1
     $call=$nlP+'        // SHARPEMU_V74_0_86_4_PRESENTER_MARK_BRIDGE_RELEASE'+$nlP+
           '        if (identity.Address != 0)'+$nlP+
           '        {'+$nlP+
           '            global::SharpEmu.Libs.Agc.AgcExports.ReleaseResidentCpuBridgeSnapshotsV740864(identity.Address);'+$nlP+
           '        }'
     $mm=$mm.Insert($insertAt,$call)
     $p=$p.Remove($mark.Start,$mark.Length).Insert($mark.Start,$mm)
     Write-Host "$script:Tag bridge_release_insertion_strategy=presenter-semicolon-after-TryAdd"
   }

   # Post-transform contracts before source write.
   if(-not $a.Contains($marker)){throw "$script:Tag AGC V86.4 marker missing after transform."}
   if(-not $p.Contains($marker)){throw "$script:Tag Presenter V86.4 marker missing after transform."}
   if((Get-Count $a '(?m)^\s*internal\s+static\s+void\s+ReleaseResidentCpuBridgeSnapshotsV740864\s*\(') -ne 1){throw "$script:Tag resident bridge helper definition count invalid."}
   if((Get-Count $p 'ReleaseResidentCpuBridgeSnapshotsV740864\(identity\.Address\)') -ne 1){throw "$script:Tag presenter bridge release call count invalid."}
   if((Get-Count $p 'SHARPEMU_V74_0_86_4_PRESENTER_MARK_BRIDGE_RELEASE') -ne 1){throw "$script:Tag presenter insertion marker count invalid."}
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
   Write-Host "$script:Tag resident_cpu_bridge_release=default-on presenter_mark_semantic=True env_0_restores_retention"
   Write-Host "$script:Tag texture_factory_anchor_required=False"
   Write-Host "$script:Tag sampled_address_anchor_required=False"
   Write-Host "$script:Tag v85_aggressive_pm4_preserved=True"
   Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True"
   Write-Host "$script:Tag Backup=$backup"
   Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
   Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
 }catch{
   if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup}
   throw
 }
}else{Write-Host "$script:Tag State=AlreadyApplied"}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_86_4_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){
 if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow}
 throw "$script:Tag BUILD FAILED. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
