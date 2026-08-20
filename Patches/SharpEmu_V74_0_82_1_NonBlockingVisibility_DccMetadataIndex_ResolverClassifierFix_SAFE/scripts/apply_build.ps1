param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$nl=if($p.Contains("`r`n")){"`r`n"}else{"`n"}
$backup=$null
$marker='SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX'
if(-not $p.Contains($marker)){
  $backup=New-Backup
  try{
    # Overall marker beside the stable V81.2 base.
    $baseMarker='    // SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR'
    $pos=$p.IndexOf($baseMarker,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag V81.2 base marker missing."}
    $p=$p.Insert($pos,"    // $marker"+$nl)

    # 1) Promote the already-existing exact non-blocking visibility path.
    # Semantics are unchanged: an ordered side effect is NOT executed early;
    # the queue is timeline-blocked and retried only after the real fence retires.
    $decl='private static readonly bool _nonBlockingOrderedVisibilityV740293 ='
    $os=$p.IndexOf($decl,[System.StringComparison]::Ordinal)
    if($os -lt 0){throw "$script:Tag ordered visibility declaration missing."}
    $osemi=$p.IndexOf(';',$os,[System.StringComparison]::Ordinal)
    if($osemi -lt 0){throw "$script:Tag ordered visibility declaration terminator missing."}
    $oseg=$p.Substring($os,$osemi-$os+1)
    if(-not $p.Contains('SHARPEMU_V74_0_82_NONBLOCKING_ORDERED_VISIBILITY_DEFAULT')){
      if($oseg.Contains('!string.Equals') -and $oseg.Contains('"0"')){
        # Compatible accumulated source already defaults on; only add the marker.
      } elseif($oseg.Contains('string.Equals') -and $oseg.Contains('"1"')){
        $oseg2=$oseg.Replace('string.Equals(','!string.Equals(')
        $oseg2=[regex]::Replace($oseg2,'(?m)^(\s*)"1",\s*$','$1"0",')
        if($oseg2 -eq $oseg){throw "$script:Tag ordered visibility transform made no change."}
        $p=$p.Remove($os,$oseg.Length).Insert($os,$oseg2)
      } else {
        throw "$script:Tag ordered visibility declaration has unknown semantics; refusing rewrite."
      }
      $lineStart=$p.LastIndexOf($nl,$os,[System.StringComparison]::Ordinal)
      if($lineStart -lt 0){$lineStart=0}else{$lineStart+=$nl.Length}
      $indent=[regex]::Match($p.Substring($lineStart,$os-$lineStart),'^\s*').Value
      $p=$p.Insert($lineStart,$indent+'// SHARPEMU_V74_0_82_NONBLOCKING_ORDERED_VISIBILITY_DEFAULT'+$nl)
    }

    # 2) Add a metadata-address bucket index after GuestImageResource is defined.
    # The index stores object references only; Consider() remains the correctness
    # authority for Initialized/shape/tile/view-format/generation checks.
    if(-not $p.Contains('SHARPEMU_V74_0_82_DCC_METADATA_INDEX')){
      $anchor='        private readonly record struct ReinterpretedGuestImageViews('
      $ap=$p.IndexOf($anchor,[System.StringComparison]::Ordinal)
      if($ap -lt 0){throw "$script:Tag ReinterpretedGuestImageViews anchor missing."}
      $helper=@'
        // SHARPEMU_V74_0_82_DCC_METADATA_INDEX
        // V81.2 runtime reached DCC_TYPED_ALIAS_REJECT=16384 while only a tiny
        // number of images share the requested DCC MetadataAddress. Cache that
        // first-stage membership so each lookup does not scan every guest image.
        // Descriptor compatibility and newest-generation selection remain in
        // TryResolveGuestImageMetadataAliasV7405632 Consider().
        private sealed class DccMetadataBucketV74082
        {
            public long Epoch;
            public int ActiveCount;
            public int VariantCount;
            public GuestImageResource[] Active = [];
            public GuestImageResource[] Variants = [];
        }

        private readonly Dictionary<ulong, DccMetadataBucketV74082>
            _dccMetadataBucketsV74082 = [];
        private long _dccMetadataEpochV74082;
        private long _v74082DccMetadataIndexHitCount;
        private long _v74082DccMetadataIndexRebuildCount;

        private void InvalidateDccMetadataIndexV74082() =>
            Interlocked.Increment(ref _dccMetadataEpochV74082);

        private DccMetadataBucketV74082 GetDccMetadataBucketV74082(
            ulong metadataAddress)
        {
            var epoch = Volatile.Read(ref _dccMetadataEpochV74082);
            if (_dccMetadataBucketsV74082.TryGetValue(
                    metadataAddress,
                    out var cached) &&
                cached.Epoch == epoch &&
                cached.ActiveCount == _guestImages.Count &&
                cached.VariantCount == _guestImageVariants.Count)
            {
                var hit = Interlocked.Increment(
                    ref _v74082DccMetadataIndexHitCount);
                if (hit <= 64 || (hit & (hit - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.82][DCC_METADATA_INDEX] action=hit " +
                        $"count={hit} meta=0x{metadataAddress:X16} " +
                        $"active_candidates={cached.Active.Length} " +
                        $"variant_candidates={cached.Variants.Length} " +
                        $"active_total={_guestImages.Count} " +
                        $"variant_total={_guestImageVariants.Count}");
                }

                return cached;
            }

            var active = new List<GuestImageResource>();
            foreach (var candidate in _guestImages.Values)
            {
                if (candidate.MetadataAddress == metadataAddress)
                {
                    active.Add(candidate);
                }
            }

            var variants = new List<GuestImageResource>();
            foreach (var candidate in _guestImageVariants.Values)
            {
                if (candidate.MetadataAddress == metadataAddress)
                {
                    variants.Add(candidate);
                }
            }

            var rebuilt = new DccMetadataBucketV74082
            {
                Epoch = epoch,
                ActiveCount = _guestImages.Count,
                VariantCount = _guestImageVariants.Count,
                Active = active.ToArray(),
                Variants = variants.ToArray(),
            };

            if (_dccMetadataBucketsV74082.Count >= 256)
            {
                _dccMetadataBucketsV74082.Clear();
            }

            _dccMetadataBucketsV74082[metadataAddress] = rebuilt;
            var rebuild = Interlocked.Increment(
                ref _v74082DccMetadataIndexRebuildCount);
            if (rebuild <= 64 || (rebuild & (rebuild - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.82][DCC_METADATA_INDEX] action=rebuild " +
                    $"count={rebuild} meta=0x{metadataAddress:X16} " +
                    $"active_candidates={rebuilt.Active.Length} " +
                    $"variant_candidates={rebuilt.Variants.Length} " +
                    $"active_total={_guestImages.Count} " +
                    $"variant_total={_guestImageVariants.Count}");
            }

            return rebuilt;
        }

'@
      $helper=$helper.Replace("`r`n","`n").Replace("`n",$nl)
      $p=$p.Insert($ap,$helper)
    }

    # 3) Replace only the two first-stage global DCC loops, bounded to the DCC resolver.
    $m=[regex]::Match($p,'(?m)^\s*private\s+bool\s+TryResolveGuestImageMetadataAliasV7405632\s*\(')
    if(-not $m.Success){throw "$script:Tag DCC resolver signature missing."}
    $tail=$p.Substring($m.Index+$m.Length)
    $next=[regex]::Match($tail,'(?m)^\s*private\s+static\s+bool\s+IsUsableGuestImageAlias\s*\(')
    if(-not $next.Success){throw "$script:Tag DCC resolver end anchor missing."}
    $mEnd=$m.Index+$m.Length+$next.Index
    $dseg=$p.Substring($m.Index,$mEnd-$m.Index)
    if(-not $dseg.Contains('SHARPEMU_V74_0_82_DCC_BUCKET_LOOKUP')){
      $loopPattern='(?ms)^(\s*)foreach\s*\(\s*var\s+candidate\s+in\s+_guestImages\.Values\s*\)\s*\{\s*Consider\s*\(\s*candidate\s*,\s*isActive:\s*true\s*\)\s*;\s*\}\s*\r?\n\s*foreach\s*\(\s*var\s+candidate\s+in\s+_guestImageVariants\.Values\s*\)\s*\{\s*Consider\s*\(\s*candidate\s*,\s*isActive:\s*false\s*\)\s*;\s*\}'
      $lm=[regex]::Match($dseg,$loopPattern)
      if(-not $lm.Success){throw "$script:Tag exact DCC active/variant loop pair not found inside resolver."}
      $indent=$lm.Groups[1].Value
      $replacement=$indent+'// SHARPEMU_V74_0_82_DCC_BUCKET_LOOKUP'+$nl+
        $indent+'var metadataBucketV74082 ='+$nl+
        $indent+'    GetDccMetadataBucketV74082(texture.MetadataAddress);'+$nl+
        $indent+'foreach (var candidate in metadataBucketV74082.Active)'+$nl+
        $indent+'{'+$nl+
        $indent+'    Consider(candidate, isActive: true);'+$nl+
        $indent+'}'+$nl+$nl+
        $indent+'foreach (var candidate in metadataBucketV74082.Variants)'+$nl+
        $indent+'{'+$nl+
        $indent+'    Consider(candidate, isActive: false);'+$nl+
        $indent+'}'
      $dseg=$dseg.Remove($lm.Index,$lm.Length).Insert($lm.Index,$replacement)
      $p=$p.Remove($m.Index,$mEnd-$m.Index).Insert($m.Index,$dseg)
    }

    # 4) Metadata can be attached later to an already-existing/retained image.
    # Invalidate only when the value actually changes; dictionary count changes
    # already invalidate buckets through ActiveCount/VariantCount.
    $assignPattern='(?ms)if\s*\(\s*target\.MetadataAddress\s*!=\s*0\s*\)\s*\{\s*(existing|retained)\.MetadataAddress\s*=\s*target\.MetadataAddress\s*;\s*\}'
    $matches=[regex]::Matches($p,$assignPattern)
    if($matches.Count -lt 2){throw "$script:Tag expected at least two MetadataAddress assignment blocks; found $($matches.Count)."}
    $orderedMatches=@($matches | Sort-Object Index -Descending)
    foreach($am in $orderedMatches){
      $name=$am.Groups[1].Value
      $indent=[regex]::Match($am.Value,'^\s*').Value
      $rep=$indent+'if (target.MetadataAddress != 0)'+$nl+
        $indent+'{'+$nl+
        $indent+'    if ('+$name+'.MetadataAddress != target.MetadataAddress)'+$nl+
        $indent+'    {'+$nl+
        $indent+'        '+$name+'.MetadataAddress = target.MetadataAddress;'+$nl+
        $indent+'        InvalidateDccMetadataIndexV74082();'+$nl+
        $indent+'    }'+$nl+
        $indent+'}'
      $p=$p.Remove($am.Index,$am.Length).Insert($am.Index,$rep)
    }

    # Validate accumulated contracts before writing.
    if(-not $p.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY')){throw "$script:Tag V81.2 compute start boundary lost."}
    if(-not $p.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY')){throw "$script:Tag V81.2 resource boundary lost."}
    if(-not $p.Contains('DCC_PROVENANCE_RECOVERY')){Write-Host "$script:Tag NOTE: V80 provenance marker not present on this accumulated source." -ForegroundColor Yellow}
    if(-not $p.Contains('SHARPEMU_V74_0_82_DCC_BUCKET_LOOKUP')){throw "$script:Tag DCC bucket lookup missing after transform."}
    if(-not $p.Contains('SHARPEMU_V74_0_82_NONBLOCKING_ORDERED_VISIBILITY_DEFAULT')){throw "$script:Tag nonblocking default marker missing."}
    $dcheck=[regex]::Match($p,'(?m)^\s*private\s+bool\s+TryResolveGuestImageMetadataAliasV7405632\s*\(')
    $dtail=$p.Substring($dcheck.Index+$dcheck.Length)
    $dnext=[regex]::Match($dtail,'(?m)^\s*private\s+static\s+bool\s+IsUsableGuestImageAlias\s*\(')
    $dcheckseg=$p.Substring($dcheck.Index,$dcheck.Length+$dnext.Index)
    if(([regex]::Matches($dcheckseg,'foreach\s*\(\s*var\s+candidate\s+in\s+_guestImages\.Values\s*\)')).Count -ne 0){throw "$script:Tag global active DCC scan still present in resolver."}
    if(([regex]::Matches($dcheckseg,'foreach\s*\(\s*var\s+candidate\s+in\s+_guestImageVariants\.Values\s*\)')).Count -ne 0){throw "$script:Tag global variant DCC scan still present in resolver."}

    Write-Utf8NoBom $script:PresenterPath $p
    Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
    Write-Host "$script:Tag ordered_visibility=nonblocking-default env_0_restores_legacy"
    Write-Host "$script:Tag dcc_lookup=metadata-indexed Consider_semantics_preserved=True"
    Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True"
    Write-Host "$script:Tag Backup=$backup"
    Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
  }catch{
    if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup}
    throw
  }
}else{
  Write-Host "$script:Tag State=AlreadyApplied"
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_82_1_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){
  if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow}
  throw "$script:Tag BUILD FAILED. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
