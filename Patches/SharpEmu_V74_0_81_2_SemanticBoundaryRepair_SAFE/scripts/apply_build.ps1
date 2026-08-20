param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$nl=if($p.Contains("`r`n")){"`r`n"}else{"`n"}
$backup=$null
$originalDccV80=$p.Contains('DCC_PROVENANCE_RECOVERY')
$marker='SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR'

if(-not $p.Contains($marker)){
    $backup=New-Backup
    try{
        # Mark correction beside V81 overall marker without replacing accumulated source.
        $overall='    // SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW'
        $opos=$p.IndexOf($overall,[System.StringComparison]::Ordinal)
        if($opos -lt 0){throw "$script:Tag V81 overall marker missing."}
        $p=$p.Insert($opos,"    // $marker"+$nl)

        # Keep bounded locality but avoid the V81 default burst=8 that was present
        # during the DeviceLost reproduction. Accept env override >=1.
        $bstart=$p.IndexOf('    private static readonly int _queueSubmissionBurstV74043 =',[System.StringComparison]::Ordinal)
        if($bstart -lt 0){throw "$script:Tag queue burst declaration missing."}
        $bsemi=$p.IndexOf(';',$bstart,[System.StringComparison]::Ordinal)
        if($bsemi -lt 0){throw "$script:Tag queue burst declaration terminator missing."}
        $bseg=$p.Substring($bstart,$bsemi-$bstart+1)
        $bseg2=[regex]::Replace($bseg,':\s*8\s*;',': 2;')
        if($bseg2 -eq $bseg -and -not($bseg -match ':\s*2\s*;')){
            throw "$script:Tag queue burst default is neither 8 nor 2; refusing ambiguous rewrite."
        }
        if($bseg2 -ne $bseg){$p=$p.Remove($bstart,$bseg.Length).Insert($bstart,$bseg2)}

        # Bound transformation to exactly ExecuteComputeDispatchCore. Do not depend
        # on the exact textual V81 if/guard shape that caused V81.1 installer failure.
        $methodMatch=[regex]::Match(
            $p,
            '(?m)^\s*private\s+void\s+ExecuteComputeDispatchCore\s*\(\s*VulkanComputeGuestDispatch\s+work\s*\)\s*\{')
        if(-not $methodMatch.Success){throw "$script:Tag ExecuteComputeDispatchCore semantic signature missing."}
        $mStart=$methodMatch.Index
        $tail=$p.Substring($mStart+$methodMatch.Length)
        $nextMatch=[regex]::Match(
            $tail,
            '(?m)^\s*private\s+void\s+TraceDeviceLostCandidateV74056\s*\(')
        if(-not $nextMatch.Success){throw "$script:Tag TraceDeviceLostCandidateV74056 boundary missing after compute method."}
        $mEnd=$mStart+$methodMatch.Length+$nextMatch.Index
        $seg=$p.Substring($mStart,$mEnd-$mStart)

        # Boundary 1: unconditional flush directly after method opening brace.
        # We intentionally leave the V81 conditional flush block untouched; this
        # insertion restores correctness regardless of its formatting.
        $startMarker='SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY'
        if(-not $seg.Contains($startMarker)){
            $open=[regex]::Match(
                $seg,
                '(?m)^(\s*)private\s+void\s+ExecuteComputeDispatchCore\s*\(\s*VulkanComputeGuestDispatch\s+work\s*\)\s*\{')
            if(-not $open.Success){throw "$script:Tag compute method opening brace missing inside bounded segment."}
            $methodIndent=$open.Groups[1].Value
            $bodyIndent=$methodIndent+'    '
            $brace=$open.Index+$open.Value.LastIndexOf('{')
            $insert=$nl+$bodyIndent+'// '+$startMarker+$nl+$bodyIndent+'FlushBatchedGuestCommands();'
            $seg=$seg.Insert($brace+1,$insert)
        }

        # Boundary 2: resource/upload work must finish before the dispatch shares
        # a later Vulkan command path. Insert immediately after the single resource
        # creation statement, independent of V81 comments/whitespace.
        $resourceMarker='SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY'
        if(-not $seg.Contains($resourceMarker)){
            $resourceMatches=[regex]::Matches(
                $seg,
                '(?m)^(\s*)resources\s*=\s*CreateComputeDispatchResources\s*\(\s*work\s*\)\s*;')
            if($resourceMatches.Count -ne 1){throw "$script:Tag expected exactly one CreateComputeDispatchResources(work) statement; found $($resourceMatches.Count)."}
            $resourceMatch=$resourceMatches[0]
            $resourceIndent=$resourceMatch.Groups[1].Value
            $insert=$nl+$nl+$resourceIndent+'// '+$resourceMarker+$nl+$resourceIndent+'FlushBatchedGuestCommands();'
            $seg=$seg.Insert($resourceMatch.Index+$resourceMatch.Length,$insert)
        }

        # Validate semantic result before touching disk.
        $startCount=([regex]::Matches($seg,[regex]::Escape($startMarker))).Count
        $resourceCount=([regex]::Matches($seg,[regex]::Escape($resourceMarker))).Count
        $flushCount=([regex]::Matches($seg,'FlushBatchedGuestCommands\s*\(\s*\)\s*;')).Count
        $resourceCallCount=([regex]::Matches($seg,'CreateComputeDispatchResources\s*\(\s*work\s*\)')).Count
        if($startCount -ne 1){throw "$script:Tag compute-start boundary count invalid: $startCount"}
        if($resourceCount -ne 1){throw "$script:Tag resource boundary count invalid: $resourceCount"}
        if($flushCount -lt 2){throw "$script:Tag expected at least two compute flush boundaries; found $flushCount."}
        if($resourceCallCount -ne 1){throw "$script:Tag resource creation call count invalid after transform: $resourceCallCount"}

        $p=$p.Remove($mStart,$mEnd-$mStart).Insert($mStart,$seg)
        Write-Utf8NoBom $script:PresenterPath $p
        $p2=Read-Utf8 $script:PresenterPath

        if(-not $p2.Contains($marker)){throw "$script:Tag correction marker missing after write."}
        if(-not $p2.Contains($startMarker)){throw "$script:Tag compute-start boundary missing after write."}
        if(-not $p2.Contains($resourceMarker)){throw "$script:Tag resource boundary missing after write."}
        if(-not $p2.Contains('SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT')){throw "$script:Tag V81 queued/inflight split unexpectedly lost."}
        if($originalDccV80 -and -not $p2.Contains('DCC_PROVENANCE_RECOVERY')){throw "$script:Tag V74.0.80 DCC provenance recovery unexpectedly lost."}

        Write-Host "$script:Tag PATCH APPLIED SEMANTICALLY." -ForegroundColor Green
        Write-Host "$script:Tag compute_start_boundary=restored-by-position"
        Write-Host "$script:Tag compute_resource_boundary=restored-by-position"
        Write-Host "$script:Tag risky_v81_blocks_preserved_but_neutralized=True"
        Write-Host "$script:Tag queue_burst_default=2 env_override_preserved=True"
        Write-Host "$script:Tag queue_inflight_split=preserved"
        Write-Host "$script:Tag Backup=$backup"
        Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
    }catch{
        if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup}
        throw
    }
}else{
    Write-Host "$script:Tag State=AlreadyApplied"
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_81_2_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){
    if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow}
    throw "$script:Tag BUILD FAILED. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
