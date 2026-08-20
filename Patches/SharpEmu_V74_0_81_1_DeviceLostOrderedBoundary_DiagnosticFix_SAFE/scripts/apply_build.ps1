param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$nl=if($p.Contains("`r`n")){"`r`n"}else{"`n"}
$changed=$false
$backup=$null
$originalDccV80=$p.Contains('DCC_PROVENANCE_RECOVERY')

if(-not $p.Contains('SHARPEMU_V74_0_81_1_DEVICE_LOST_ORDERED_BOUNDARY_FIX')){
    $backup=New-Backup
    try{
        # Overall correction marker beside the V81 marker.
        $overall='    // SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW'
        $opos=$p.IndexOf($overall,[System.StringComparison]::Ordinal)
        if($opos -lt 0){throw "$script:Tag V81 overall marker missing."}
        $p=$p.Insert($opos,"    // SHARPEMU_V74_0_81_1_DEVICE_LOST_ORDERED_BOUNDARY_FIX"+$nl)
        $changed=$true

        # V81 burst=8 did not materially improve batch average and can starve
        # cross-queue producer progress. Keep a small bounded locality burst=2.
        $bstart=$p.IndexOf('    private static readonly int _queueSubmissionBurstV74043 =',[System.StringComparison]::Ordinal)
        if($bstart -lt 0){throw "$script:Tag queue burst declaration missing."}
        $bsemi=$p.IndexOf(';',$bstart,[System.StringComparison]::Ordinal)
        if($bsemi -lt 0){throw "$script:Tag queue burst declaration terminator missing."}
        $bseg=$p.Substring($bstart,$bsemi-$bstart+1)
        if($bseg -match ':\s*8\s*;'){$bseg2=[regex]::Replace($bseg,':\s*8\s*;',': 2;');$p=$p.Remove($bstart,$bseg.Length).Insert($bstart,$bseg2);$changed=$true}
        elseif(-not($bseg -match ':\s*2\s*;')){throw "$script:Tag queue burst default is neither V81=8 nor corrected=2; refusing ambiguous rewrite."}

        $mStart=$p.IndexOf('        private void ExecuteComputeDispatchCore(VulkanComputeGuestDispatch work)',[System.StringComparison]::Ordinal)
        $mEnd=$p.IndexOf('        private void TraceDeviceLostCandidateV74056(', $mStart,[System.StringComparison]::Ordinal)
        if($mStart -lt 0 -or $mEnd -lt 0){throw "$script:Tag ExecuteComputeDispatchCore bounds missing."}
        $seg=$p.Substring($mStart,$mEnd-$mStart)

        # Restore the original boundary before any new compute resource/command work.
        $oldStart='            // SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR'+$nl+
                  '            if (!_preservePayloadBatchV7405620)'+$nl+
                  '            {'+$nl+
                  '                FlushBatchedGuestCommands();'+$nl+
                  '            }'
        $newStart='            // SHARPEMU_V74_0_81_1_COMPUTE_START_FENCE_BOUNDARY'+$nl+
                  '            FlushBatchedGuestCommands();'
        if($seg.Contains($oldStart)){$seg=$seg.Replace($oldStart,$newStart);$changed=$true}
        elseif(-not $seg.Contains('SHARPEMU_V74_0_81_1_COMPUTE_START_FENCE_BOUNDARY')){throw "$script:Tag V81 risky compute-start block not found."}

        # Restore the resource/upload boundary removed by V81. This is the key
        # correctness boundary before a dispatch may share the guest command path.
        $oldResource='                resources = CreateComputeDispatchResources(work);'+$nl+$nl+
                     '                // V74.0.81: keep an already-open payload batch alive while'+$nl+
                     '                // this dispatch is eligible for the shared command buffer.'+$nl+
                     '                var adaptiveUnifiedV7405616 ='
        $newResource='                resources = CreateComputeDispatchResources(work);'+$nl+$nl+
                     '                // SHARPEMU_V74_0_81_1_RESOURCE_UPLOAD_FENCE_BOUNDARY'+$nl+
                     '                FlushBatchedGuestCommands();'+$nl+$nl+
                     '                var adaptiveUnifiedV7405616 ='
        if($seg.Contains($oldResource)){$seg=$seg.Replace($oldResource,$newResource);$changed=$true}
        elseif(-not $seg.Contains('SHARPEMU_V74_0_81_1_RESOURCE_UPLOAD_FENCE_BOUNDARY')){throw "$script:Tag V81 removed resource-boundary block not found."}

        # V81 added a shared-only flush later in the method. Once the required
        # resource boundary is restored, this guard is redundant and would double-flush.
        $oldGuard='                // Standalone/indirect/multi-submit compute still requires a real'+$nl+
                  '                // submit boundary. Only the proven shared path crosses payloads.'+$nl+
                  '                if (!useSharedComputeBatchV7405617)'+$nl+
                  '                {'+$nl+
                  '                    FlushBatchedGuestCommands();'+$nl+
                  '                }'+$nl+$nl
        if($seg.Contains($oldGuard)){$seg=$seg.Replace($oldGuard,'');$changed=$true}

        # Require both restored boundaries inside this method.
        if(-not $seg.Contains('SHARPEMU_V74_0_81_1_COMPUTE_START_FENCE_BOUNDARY')){throw "$script:Tag start fence boundary missing after transform."}
        if(-not $seg.Contains('SHARPEMU_V74_0_81_1_RESOURCE_UPLOAD_FENCE_BOUNDARY')){throw "$script:Tag resource fence boundary missing after transform."}
        $flushCount=([regex]::Matches($seg,'FlushBatchedGuestCommands\s*\(\s*\)\s*;')).Count
        if($flushCount -lt 2){throw "$script:Tag expected at least two compute flush boundaries after repair; found $flushCount."}

        $p=$p.Remove($mStart,$mEnd-$mStart).Insert($mStart,$seg)
        Write-Utf8NoBom $script:PresenterPath $p
        $p2=Read-Utf8 $script:PresenterPath
        if(-not $p2.Contains('SHARPEMU_V74_0_81_1_DEVICE_LOST_ORDERED_BOUNDARY_FIX')){throw "$script:Tag correction marker missing after write."}
        if(-not $p2.Contains('SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT')){throw "$script:Tag V81 queued/inflight split unexpectedly lost."}
        if($originalDccV80 -and -not $p2.Contains('DCC_PROVENANCE_RECOVERY')){throw "$script:Tag V74.0.80 DCC provenance recovery unexpectedly lost."}
        if($p2.Contains('V74.0.81: keep an already-open payload batch alive while')){throw "$script:Tag unsafe V81 resource-boundary removal still present."}
        Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY."
        Write-Host "$script:Tag compute_start_boundary=restored"
        Write-Host "$script:Tag compute_resource_boundary=restored"
        Write-Host "$script:Tag queue_burst_default=2 env_override_preserved=True"
        Write-Host "$script:Tag queue_inflight_split=preserved"
        Write-Host "$script:Tag Backup=$backup"
        Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
    }catch{Restore-Backup $backup;throw}
}else{
    Write-Host "$script:Tag State=AlreadyApplied"
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_81_1_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){
 if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow}
 throw "$script:Tag BUILD FAILED. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
