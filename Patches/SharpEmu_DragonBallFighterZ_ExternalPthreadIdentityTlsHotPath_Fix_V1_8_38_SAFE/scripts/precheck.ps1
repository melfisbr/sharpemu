param(
    [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin',
    [switch]$NoTranscript
)
. (Join-Path $PSScriptRoot "common.ps1")
$t=Start-V1838Transcript "DBFZ_V1_8_38_RUN2_PRECHECK.log" -NoTranscript:$NoTranscript
try {
    if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){throw "EBOOT not found: $Game"}
    $sha=Get-Sha256Lower $Game
    Write-Host "[DBFZ-CPU-1838] EBOOT_SHA256=$sha"
    if($sha -ne '106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018'){throw "Unexpected DBFZ eboot SHA256."}
    $s=Read-V1838SourceSet
    Assert-V1838Prerequisites $s
    $state=Get-V1838State $s.DirectImports $s.Pthread $s.PthreadExt
    Write-Host "[DBFZ-CPU-1838] State=$state"
    if($state -eq 'Partial'){throw "V1.8.38 source state is partial/divergent."}
    if($state -eq 'Baseline'){
        $p=Patch-AllV1838 $s
        $dry=Get-V1838State $p.DirectImports $p.Pthread $p.PthreadExt
        $checks=[ordered]@{
            direct_marker=$p.DirectImports.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_IDENTITY_TLS_HOTPATH_V1_8_38")
            direct_external_recovery=$p.DirectImports.Contains("externalPthreadIdentityV1838")
            direct_external_context_register=$p.DirectImports.Contains("RegisterGuestThreadContext(guestThreadHandle, cpuContext);")
            direct_explicit_tls_call=$p.DirectImports.Contains("TryGetSpecificForThreadHandleFastV1838")
            direct_mutex_default_gate_preserved=$p.DirectImports.Contains("_pthreadMutexImportHotPathV1827Enabled")
            pthread_bridge=$p.Pthread.Contains("GetCurrentExternalPthreadHandleFastV1838")
            pthreadext_explicit_tls=$p.PthreadExt.Contains("TryGetSpecificForThreadHandleFastV1838")
            waiter_v1837_preserved=$s.Guest.Contains("SHARPEMU_DBFZ_COOPERATIVE_WAITER_LANE_RELEASE_V1_8_37")
            apr_v1837_preserved=$s.Apr.Contains("SHARPEMU_DBFZ_APR_COOPERATIVE_WAIT_V1_8_37")
            dry_state_applied=($dry -eq 'Applied')
        }
        foreach($kv in $checks.GetEnumerator()){
            Write-Host "[DBFZ-CPU-1838] dry_$($kv.Key)=$($kv.Value)"
            if(-not $kv.Value){throw "Dry-run check failed: $($kv.Key)"}
        }
    }
    Write-Host "[DBFZ-CPU-1838] PRECHECK PASSED."
} finally { Stop-V1838Transcript $t }
