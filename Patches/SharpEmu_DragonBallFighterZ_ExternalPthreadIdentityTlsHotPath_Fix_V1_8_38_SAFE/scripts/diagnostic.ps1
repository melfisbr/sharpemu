param(
    [int]$Seconds=240,
    [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin',
    [switch]$NoTranscript
)
. (Join-Path $PSScriptRoot "common.ps1")
$t=Start-V1838Transcript "DBFZ_V1_8_38_RUN5_DIAGNOSTIC.log" -NoTranscript:$NoTranscript
try {
    & (Join-Path $PSScriptRoot 'precheck.ps1') -Game $Game -NoTranscript
    & (Join-Path $PSScriptRoot 'post_audit.ps1') -NoTranscript
    $repo=Find-RepoRoot
    $patches=Get-PatchesRoot
    $exe=Resolve-SharpEmuExecutable $repo
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $prefix='DBFZ_EXTERNAL_PTHREAD_V1_8_38_'+$stamp
    $stdout=Join-Path $patches ($prefix+'_stdout.log')
    $stderr=Join-Path $patches ($prefix+'_stderr.log')
    Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force

    $managed=@(
        'SHARPEMU_APR_PAK_READAHEAD','SHARPEMU_APR_ASYNC_PIPELINE',
        'SHARPEMU_PTHREAD_IMPORT_HOTPATH','SHARPEMU_PTHREAD_IDENTITY_TLS_HOTPATH',
        'SHARPEMU_PTHREAD_MUTEX_IMPORT_HOTPATH','SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC',
        'SHARPEMU_DBFZ_WAITER_TRACE','SHARPEMU_DBFZ_EXTERNAL_PTHREAD_TRACE',
        'SHARPEMU_LOG_GUEST_THREADS','SHARPEMU_LOG_AGC','SHARPEMU_PERF_HLE'
    )
    $old=@{}
    foreach($n in $managed){$old[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
    $env:SHARPEMU_APR_PAK_READAHEAD='0'
    $env:SHARPEMU_APR_ASYNC_PIPELINE='1'
    $env:SHARPEMU_PTHREAD_IMPORT_HOTPATH='1'
    $env:SHARPEMU_PTHREAD_IDENTITY_TLS_HOTPATH='1'
    $env:SHARPEMU_PTHREAD_MUTEX_IMPORT_HOTPATH='0'
    $env:SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC='1'
    $env:SHARPEMU_DBFZ_WAITER_TRACE='1'
    $env:SHARPEMU_DBFZ_EXTERNAL_PTHREAD_TRACE='1'
    $env:SHARPEMU_LOG_GUEST_THREADS='0'
    $env:SHARPEMU_LOG_AGC='0'
    $env:SHARPEMU_PERF_HLE='0'

    $specs=@(
        [pscustomobject]@{Value=8388608L;Name='Import8M'},
        [pscustomobject]@{Value=16777216L;Name='Import16M'},
        [pscustomobject]@{Value=25165824L;Name='Import24M'},
        [pscustomobject]@{Value=33554432L;Name='Import32M'},
        [pscustomobject]@{Value=41943040L;Name='Import40M'},
        [pscustomobject]@{Value=50331648L;Name='Import48M'},
        [pscustomobject]@{Value=58720256L;Name='Import56M'},
        [pscustomobject]@{Value=67108864L;Name='Import64M'},
        [pscustomobject]@{Value=75497472L;Name='Import72M'},
        [pscustomobject]@{Value=83886080L;Name='Import80M'},
        [pscustomobject]@{Value=92274688L;Name='Import88M'}
    )
    $milestones=[ordered]@{
        Import8M=-1L;Import16M=-1L;Import24M=-1L;Import32M=-1L;Import40M=-1L;
        Import48M=-1L;Import56M=-1L;Import64M=-1L;Import72M=-1L;Import80M=-1L;
        Import88M=-1L;Vulkan=-1L;Splash=-1L
    }
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $p=$null;$runError=$null;$stopped=$false;$exitCode=-999999
    try {
        Write-Host "[DBFZ-CPU-1838] External root pthread identity/TLS hotpath diagnostic starting."
        $p=Start-Process -FilePath $exe -ArgumentList @($Game) -WorkingDirectory (Split-Path -Parent $exe) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $deadline=(Get-Date).AddSeconds($Seconds)
        while(-not $p.HasExited -and (Get-Date) -lt $deadline){
            Start-Sleep -Milliseconds 250
            $p.Refresh()
            if(-not(Test-Path -LiteralPath $stderr -PathType Leaf)){continue}
            $tail=@(Get-Content -LiteralPath $stderr -Tail 1900 -ErrorAction SilentlyContinue)
            $now=$sw.ElapsedMilliseconds
            foreach($s in $specs){
                $n=[string]$s.Name
                if($milestones[$n]-lt 0 -and ($tail -match ('dbfz\.import_progress\.v1892 import='+[long]$s.Value))){$milestones[$n]=$now}
            }
            if($milestones.Vulkan -lt 0 -and ($tail -match 'Vulkan device:')){$milestones.Vulkan=$now}
            if($milestones.Splash -lt 0 -and ($tail -match 'Vulkan VideoOut presented splash')){$milestones.Splash=$now}
        }
        $p.Refresh()
        if($p.HasExited){try{$exitCode=$p.ExitCode}catch{$exitCode=-999998}}else{$stopped=$true}
    } catch {$runError=$_}
    finally {
        if($null -ne $p -and -not $p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
        $sw.Stop()
        foreach($n in $managed){
            if($null -eq $old[$n]){Remove-Item ('Env:'+$n) -ErrorAction SilentlyContinue}
            else{[Environment]::SetEnvironmentVariable($n,$old[$n],'Process')}
        }
    }

    $lines=if(Test-Path -LiteralPath $stderr -PathType Leaf){@(Get-Content -LiteralPath $stderr)}else{@()}
    $progress=@($lines|Select-String -Pattern 'dbfz\.import_progress\.v1892 import=')
    $externalHot=@($lines|Select-String -Pattern '\[DBFZ-CPU-1838\] external_identity_tls_hotpath')
    [long]$externalMax=0
    $guestSet=New-Object 'System.Collections.Generic.HashSet[string]'
    foreach($hit in $externalHot){
        $m=[regex]::Match($hit.Line,' n=(\d+) .*guest=0x([0-9A-Fa-f]+)')
        if($m.Success){
            [long]$n=0
            if([long]::TryParse($m.Groups[1].Value,[ref]$n) -and $n -gt $externalMax){$externalMax=$n}
            [void]$guestSet.Add($m.Groups[2].Value.ToUpperInvariant())
        }
    }
    $hotThreads=@($lines|Select-String -Pattern '\[DBFZ-CPU-1827\] hotpath_thread_active')
    $aprHost=@($lines|Select-String -Pattern '\[DBFZ-WAIT-1837\] apr_host_wait')
    $aprCoop=@($lines|Select-String -Pattern '\[DBFZ-WAIT-1837\] apr_coop_block')
    $joinHost=@($lines|Select-String -Pattern '\[DBFZ-WAIT-1837\] join_host')
    $joinCoop=@($lines|Select-String -Pattern '\[DBFZ-WAIT-1837\] join_coop')
    $aprZero=@($aprHost|Where-Object{$_.Line -match 'guest=0x0000000000000000'})
    $timeoutWake=@($lines|Select-String -Pattern 'TIMEOUT_WAKE|guest_threads\.timeout_wake')
    $unresolved=@($lines|Select-String -Pattern 'unresolved:')
    $fatal=@($lines|Select-String -Pattern 'LowLevelFatalError|Fatal error|DeviceLost|Native exception|AccessViolation')
    $mkdirExists=@($lines|Select-String -Pattern 'ORBIS_GEN2_ERROR_ALREADY_EXISTS \(1-LFLmRFxxM\)')
    $draw=@($lines|Select-String -Pattern 'agc\.draw_stream_replay_parsed')
    $fb=@($lines|Select-String -Pattern 'agc\.cb_metadata_fb_clear ')
    $flip=@($lines|Select-String -Pattern 'videoout\.submit_flip')

    $base371=@{
        Import8M=20871L;Import16M=31326L;Import24M=41242L;Import32M=52050L;Import40M=64863L;
        Import48M=75948L;Import56M=84446L;Import64M=93154L;Import72M=112027L;Import80M=138924L;
        Import88M=198426L;Vulkan=200632L;Splash=201186L
    }
    $base35=@{
        Import8M=20150L;Import16M=30206L;Import24M=39696L;Import32M=50124L;Import40M=62348L;
        Import48M=72554L;Import56M=80665L;Import64M=89003L;Import72M=107427L;Import80M=136747L;
        Import88M=188433L;Vulkan=191973L;Splash=192239L
    }

    $summary=New-Object System.Collections.Generic.List[string]
    $summary.Add('Dragon Ball FighterZ External Root Pthread Identity/TLS Hotpath V1.8.38')
    $summary.Add("DiagnosticSeconds=$Seconds")
    $summary.Add("TotalProcessMs=$($sw.ElapsedMilliseconds)")
    $summary.Add("StoppedByDiagnostic=$stopped")
    $summary.Add("ProcessExitCode=$exitCode")
    foreach($n in $milestones.Keys){
        $summary.Add("$($n)ObservedMs=$($milestones[$n])")
        if($milestones[$n]-ge 0){
            $summary.Add("$($n)DeltaVsV18371Ms=$($milestones[$n]-[long]$base371[$n])")
            $summary.Add("$($n)DeltaVsV1835Ms=$($milestones[$n]-[long]$base35[$n])")
        }
    }
    $summary.Add("ExternalIdentityTlsHotpathSampleCount=$($externalHot.Count)")
    $summary.Add("ExternalIdentityTlsHotpathMaxObservedN=$externalMax")
    $summary.Add("ExternalIdentityTlsHotpathGuestUniqueCount=$($guestSet.Count)")
    $summary.Add("ExistingManagedHotpathThreadSampleCount=$($hotThreads.Count)")
    $summary.Add("AprHostWaitFallbackSampleCount=$($aprHost.Count)")
    $summary.Add("AprHostWaitZeroGuestSampleCount=$($aprZero.Count)")
    $summary.Add("AprCooperativeBlockSampleCount=$($aprCoop.Count)")
    $summary.Add("PthreadJoinHostFallbackSampleCount=$($joinHost.Count)")
    $summary.Add("PthreadJoinCooperativeSampleCount=$($joinCoop.Count)")
    $summary.Add("TimeoutWakeSampleCount=$($timeoutWake.Count)")
    $summary.Add("MkdirAlreadyExistsWarningCount=$($mkdirExists.Count)")
    $summary.Add("UnresolvedImportCount=$($unresolved.Count)")
    $summary.Add("FatalCount=$($fatal.Count)")
    $summary.Add("DrawStreamReplayParsedCount=$($draw.Count)")
    $summary.Add("MetadataFramebufferClearCount=$($fb.Count)")
    $summary.Add("VideoOutSubmitFlipCount=$($flip.Count)")

    $summaryPath=Join-Path $patches ($prefix+'_SUMMARY.txt')
    $summary|Set-Content -LiteralPath $summaryPath -Encoding utf8
    $progress.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_IMPORT_PROGRESS.log')) -Encoding utf8
    $externalHot.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_EXTERNAL_PTHREAD_HOTPATH.log')) -Encoding utf8
    $hotThreads.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_MANAGED_PTHREAD_HOTPATH.log')) -Encoding utf8
    $aprHost.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_APR_HOST_FALLBACK.log')) -Encoding utf8
    $aprCoop.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_APR_COOP.log')) -Encoding utf8
    $joinHost.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_JOIN_HOST.log')) -Encoding utf8
    $joinCoop.Line|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_JOIN_COOP.log')) -Encoding utf8
    $lines|Select-Object -Last 2600|Set-Content -LiteralPath (Join-Path $patches ($prefix+'_FINAL_2600_LINES.log')) -Encoding utf8

    $analysisPath=Join-Path $patches ($prefix+'_ROOT_CAUSE_AUDIT.txt')
    @(
        'root_top_level_guest_handle=0 by RunTopLevelGuestEntryStub baseline',
        'KernelPthreadState=root raw worker already owns stable synthetic pthread identity',
        'V1.8.38=recovers that identity only inside pthread identity/TLS import hotpath',
        'GuestThreadExecution.CurrentGuestThreadHandle=not overwritten by V1.8.38',
        'APR/join root waits=remain host fallback; scheduler ownership semantics preserved',
        'mutex_import_hotpath=remains OFF in diagnostic and external identity recovery is not attempted for mutex kind'
    )|Set-Content -LiteralPath $analysisPath -Encoding utf8

    $zip=Join-Path $patches ('DBFZ_EXTERNAL_PTHREAD_V1_8_38_RESULT_'+$stamp+'.zip')
    $toZip=@(
        $stdout,$stderr,$summaryPath,$analysisPath,
        (Join-Path $patches ($prefix+'_IMPORT_PROGRESS.log')),
        (Join-Path $patches ($prefix+'_EXTERNAL_PTHREAD_HOTPATH.log')),
        (Join-Path $patches ($prefix+'_MANAGED_PTHREAD_HOTPATH.log')),
        (Join-Path $patches ($prefix+'_APR_HOST_FALLBACK.log')),
        (Join-Path $patches ($prefix+'_APR_COOP.log')),
        (Join-Path $patches ($prefix+'_JOIN_HOST.log')),
        (Join-Path $patches ($prefix+'_JOIN_COOP.log')),
        (Join-Path $patches ($prefix+'_FINAL_2600_LINES.log'))
    )
    Compress-Archive -LiteralPath $toZip -DestinationPath $zip -Force
    Write-Host "[DBFZ-CPU-1838] RESULT ZIP: $zip"
    if($null -ne $runError){throw $runError}
    Write-Host "[DBFZ-CPU-1838] DIAGNOSTIC COMPLETED."
} finally { Stop-V1838Transcript $t }
