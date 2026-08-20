param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$a=$s.Agc;$nl=if($a.Contains("`r`n")){"`r`n"}else{"`n"};$backup=$null
$marker='SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE'
if(-not $a.Contains($marker)){
 $backup=New-Backup
 try{
   foreach($name in @('_kytyPm4BlockedSchedulerV74030','_kytyInlineWriteDataV74030')){
     $d=Get-DeclarationSegment $a $name;if($null -eq $d){throw "$script:Tag declaration missing: $name"}
     if(-not($d.Text.Contains('!string.Equals') -and $d.Text.Contains('"0"'))){
       if($d.Text.Contains('string.Equals') -and -not $d.Text.Contains('!string.Equals') -and $d.Text.Contains('"1"')){
         $rep=$d.Text.Replace('string.Equals(','!string.Equals(');$rep=[regex]::Replace($rep,'(?m)^(\s*)"1",\s*$','$1"0",');if($rep -eq $d.Text){throw "$script:Tag failed default-on transform: $name"};$a=$a.Remove($d.Start,$d.Length).Insert($d.Start,$rep)
       }else{throw "$script:Tag unknown declaration form: $name"}
     }
   }
   $fieldAnchor='private static long _v74030InlineWriteDataTraceCount;'
   $pos=$a.IndexOf($fieldAnchor,[System.StringComparison]::Ordinal);if($pos -lt 0){throw "$script:Tag V74030 trace field anchor missing."}
   $eol=$a.IndexOf($nl,$pos,[System.StringComparison]::Ordinal);if($eol -lt 0){throw "$script:Tag field EOL missing."};$insert=$eol+$nl.Length
   $fields=@"
    // $marker
    // Aggressive path: preserve real Vulkan queue completion, but avoid global
    // GPU-buffer readback for RELEASE_MEM labels and duplicate multi-MB payloads
    // inside one draw/dispatch. Every switch accepts env=0 for instant rollback.
    private static readonly bool _releaseMemQueueCompletionOnlyV74085 =
        !string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_RELEASE_MEM_QUEUE_COMPLETION_ONLY"), "0", StringComparison.Ordinal);
    private static readonly bool _localTexturePayloadDedupV74085 =
        !string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOCAL_TEXTURE_PAYLOAD_DEDUP"), "0", StringComparison.Ordinal);
    private const long V74085LocalTexturePayloadDedupThresholdBytes = 1L * 1024L * 1024L;
    private static long _v74085LocalTexturePayloadDedupCount;
    private static long _v74085LocalTexturePayloadDedupBytes;
    private static long _v74085ReleaseQueueOnlyTraceCount;
    private readonly record struct V74085LocalTexturePayloadKey(
        ulong Address, uint Width, uint Height, uint Format, uint NumberType,
        uint TileMode, uint Type, uint BaseLevel, uint LastLevel, uint Pitch,
        uint Depth, uint BaseArray, uint ArrayPitch, uint MaxMip, uint BcSwizzle,
        ulong MetadataAddress, uint DescriptorFlags, bool HasExtendedDescriptor,
        uint MipLevel, bool IsArrayed);
"@ -replace "`n",$nl
   $a=$a.Insert($insert,$fields)

   $tex=Get-MethodSegment $a 'CreateGuestDrawTextures';if($null -eq $tex){throw "$script:Tag texture method vanished."}
   $m=$tex.Text
   $anchor="        fallbackTextureCount = 0;${nl}        foreach (var binding in bindings)"
   if(-not $m.Contains($anchor)){throw "$script:Tag texture dictionary anchor missing."}
   $replacement="        fallbackTextureCount = 0;${nl}        Dictionary<V74085LocalTexturePayloadKey, GuestDrawTexture>? v74085Seen =${nl}            _localTexturePayloadDedupV74085${nl}                ? new Dictionary<V74085LocalTexturePayloadKey, GuestDrawTexture>()${nl}                : null;${nl}        foreach (var binding in bindings)"
   $m=$m.Replace($anchor,$replacement)
   $loopAnchor="        {${nl}            var descriptorAddress = binding.Descriptor.Address;"
   if(-not $m.Contains($loopAnchor)){throw "$script:Tag texture loop anchor missing."}
   $dedup=@"
        {
            var descriptorAddress = binding.Descriptor.Address;
            var dV74085 = binding.Descriptor;
            var keyV74085 = new V74085LocalTexturePayloadKey(
                dV74085.Address, dV74085.Width, dV74085.Height,
                dV74085.Format, dV74085.NumberType, dV74085.TileMode,
                dV74085.Type, dV74085.BaseLevel, dV74085.LastLevel,
                dV74085.Pitch, dV74085.Depth, dV74085.BaseArray,
                dV74085.ArrayPitch, dV74085.MaxMip, dV74085.BcSwizzle,
                dV74085.MetadataAddress, dV74085.DescriptorFlags,
                dV74085.HasExtendedDescriptor, binding.MipLevel,
                binding.IsArrayed);
            if (v74085Seen is not null &&
                !binding.IsStorage &&
                v74085Seen.TryGetValue(keyV74085, out var firstV74085))
            {
                var bytesV74085 =
                    firstV74085.RgbaPixels.LongLength +
                    (firstV74085.TiledSource?.LongLength ?? 0L);
                if (bytesV74085 >= V74085LocalTexturePayloadDedupThresholdBytes)
                {
                    textures.Add(firstV74085 with
                    {
                        RgbaPixels = [],
                        TiledSource = null,
                        DstSelect = dV74085.DstSelect,
                        Sampler = ToGuestSampler(binding.SamplerDescriptor),
                    });
                    var dedupCountV74085 = Interlocked.Increment(
                        ref _v74085LocalTexturePayloadDedupCount);
                    var dedupBytesV74085 = Interlocked.Add(
                        ref _v74085LocalTexturePayloadDedupBytes,
                        bytesV74085);
                    if (dedupCountV74085 <= 256 ||
                        (dedupCountV74085 & (dedupCountV74085 - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.85][LOCAL_TEXTURE_PAYLOAD_DEDUP] " +
                            $"count={dedupCountV74085} addr=0x{dV74085.Address:X16} " +
                            $"size={dV74085.Width}x{dV74085.Height} " +
                            $"bytes={bytesV74085} skipped_mb={dedupBytesV74085 / (1024 * 1024)}");
                    }
                    continue;
                }
            }
"@ -replace "`n",$nl
   $m=$m.Replace($loopAnchor,$dedup)
   $storeAnchor="                if (texture.IsFallback)${nl}                {${nl}                    fallbackTextureCount++;${nl}                }"
   if(-not $m.Contains($storeAnchor)){throw "$script:Tag texture store anchor missing."}
   $store=$storeAnchor+"${nl}                if (v74085Seen is not null && !binding.IsStorage && !texture.IsFallback)${nl}                {${nl}                    var payloadBytesV74085 = texture.RgbaPixels.LongLength +${nl}                        (texture.TiledSource?.LongLength ?? 0L);${nl}                    if (payloadBytesV74085 >= V74085LocalTexturePayloadDedupThresholdBytes)${nl}                    {${nl}                        v74085Seen[keyV74085] = texture;${nl}                    }${nl}                }"
   $m=$m.Replace($storeAnchor,$store)
   $a=$a.Remove($tex.Start,$tex.Length).Insert($tex.Start,$m)

   foreach($methodName in @('ApplySubmittedStandardReleaseMem','ApplySubmittedReleaseMem')){
     $seg=Get-MethodSegment $a $methodName;if($null -eq $seg){throw "$script:Tag release method missing: $methodName"}
     $body=$seg.Text
     if(-not $body.Contains('requiresGpuBufferReadback: !_releaseMemQueueCompletionOnlyV74085')){
       if($methodName -eq 'ApplySubmittedStandardReleaseMem'){
         $tail='            writesGuestMemory ? writeLength : 0);'
         $new='            writesGuestMemory ? writeLength : 0,'+$nl+'            requiresGpuBufferReadback: !_releaseMemQueueCompletionOnlyV74085);'
       }else{
         $tail='            writeLength);'
         $new='            writeLength,'+$nl+'            requiresGpuBufferReadback: !_releaseMemQueueCompletionOnlyV74085);'
       }
       $idx=$body.LastIndexOf($tail,[System.StringComparison]::Ordinal);if($idx -lt 0){throw "$script:Tag RELEASE_MEM tail anchor missing in $methodName"}
       $body=$body.Remove($idx,$tail.Length).Insert($idx,$new)
       $a=$a.Remove($seg.Start,$seg.Length).Insert($seg.Start,$body)
     }
   }

   $side=Get-MethodSegment $a 'SubmitOrderedGpuSideEffect';if($null -eq $side){throw "$script:Tag side-effect method missing."}
   $sm=$side.Text
   $traceAnchor='        var producer = RegisterLabelProducer('
   if(-not $sm.Contains($traceAnchor)){throw "$script:Tag side-effect producer anchor missing."}
   $trace=@"
        if (_releaseMemQueueCompletionOnlyV74085 &&
            !requiresGpuBufferReadback &&
            debugName.StartsWith("release_mem", StringComparison.Ordinal))
        {
            var releaseQueueCountV74085 = Interlocked.Increment(
                ref _v74085ReleaseQueueOnlyTraceCount);
            if (releaseQueueCountV74085 <= 256 ||
                (releaseQueueCountV74085 & (releaseQueueCountV74085 - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.85][RELEASE_QUEUE_ONLY] count={releaseQueueCountV74085} " +
                    $"queue={state.QueueName} submission={state.ActiveSubmissionId} " +
                    $"packet=0x{packetAddress:X16} name='{debugName}'");
            }
        }

        var producer = RegisterLabelProducer(
"@ -replace "`n",$nl
   $sm=$sm.Replace($traceAnchor,$trace)
   $a=$a.Remove($side.Start,$side.Length).Insert($side.Start,$sm)

   $pm4=Get-DeclarationSegment $a '_kytyPm4BlockedSchedulerV74030';$inline=Get-DeclarationSegment $a '_kytyInlineWriteDataV74030'
   if(-not($pm4.Text.Contains('!string.Equals') -and $pm4.Text.Contains('"0"'))){throw "$script:Tag PM4 scheduler not default-on after transform."}
   if(-not($inline.Text.Contains('!string.Equals') -and $inline.Text.Contains('"0"'))){throw "$script:Tag inline WRITE_DATA not default-on after transform."}
   if((Get-Count $a 'LOCAL_TEXTURE_PAYLOAD_DEDUP') -lt 1){throw "$script:Tag local dedup marker missing after transform."}
   if((Get-Count $a 'requiresGpuBufferReadback:\s*!_releaseMemQueueCompletionOnlyV74085') -lt 2){throw "$script:Tag both RELEASE_MEM paths were not converted."}
   if(-not $s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -or -not $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY')){throw "$script:Tag V81.2 boundaries missing in preserved Presenter."}
   Write-Utf8NoBom $script:AgcPath $a
   Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
   Write-Host "$script:Tag pm4_blocked_scheduler=default-on env_0_restores_legacy"
   Write-Host "$script:Tag inline_write_data=default-on env_0_restores_legacy"
   Write-Host "$script:Tag local_texture_payload_dedup=default-on threshold_mb=1 env_0_restores_legacy"
   Write-Host "$script:Tag release_mem=queue-completion-only no_global_dirty_buffer_readback env_0_restores_legacy"
   Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True v82_nonblocking_preserved=True v84_adaptive_preserved=True"
   Write-Host "$script:Tag Backup=$backup"
   Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
 }catch{if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup};throw}
}else{Write-Host "$script:Tag State=AlreadyApplied"}
$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_85_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow};throw "$script:Tag BUILD FAILED. Log=$buildLog"}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
