param([switch]$NoTranscript)
. (Join-Path $PSScriptRoot "common.ps1")
$t=Start-V1838Transcript "DBFZ_V1_8_38_RUN4_POST_AUDIT.log" -NoTranscript:$NoTranscript
try {
    $s=Read-V1838SourceSet
    $checks=[ordered]@{
        marker=$s.DirectImports.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_IDENTITY_TLS_HOTPATH_V1_8_38")
        explicit_tls_helper=$s.PthreadExt.Contains("SHARPEMU_DBFZ_EXPLICIT_TLS_HANDLE_FASTPATH_V1_8_38")
        external_handle_bridge=$s.Pthread.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_HANDLE_BRIDGE_V1_8_38")
        external_recovery_only_identity_tls=$s.DirectImports.Contains("pthreadHotKindV1834 == PthreadHotKindIdentityV1834") -and $s.DirectImports.Contains("pthreadHotKindV1834 == PthreadHotKindTlsGetV1834")
        external_context_registration=$s.DirectImports.Contains("RegisterGuestThreadContext(guestThreadHandle, cpuContext);")
        explicit_tls_dispatch=$s.DirectImports.Contains("TryGetSpecificForThreadHandleFastV1838")
        current_guest_not_overwritten=(-not $s.DirectImports.Contains("EnterGuestThread(guestThreadHandle"))
        mutex_hotpath_default_gate_preserved=$s.DirectImports.Contains("_pthreadMutexImportHotPathV1827Enabled")
        v1834_kind_preclass_preserved=$s.DirectImports.Contains("SHARPEMU_PTHREAD_HOT_KIND_PRECLASS_V1_8_34_1")
        v1827_safe_split_preserved=$s.DirectImports.Contains("SHARPEMU_PTHREAD_SAFE_SPLIT_V1_8_27")
        waiter_v1837_preserved=$s.Guest.Contains("SHARPEMU_DBFZ_COOPERATIVE_WAITER_LANE_RELEASE_V1_8_37")
        apr_v1837_preserved=$s.Apr.Contains("SHARPEMU_DBFZ_APR_COOPERATIVE_WAIT_V1_8_37")
        external_thread_scheduler_classification_preserved=$s.DirectCore.Contains("return _guestThreads.ContainsKey(guestThreadHandle);")
    }
    foreach($kv in $checks.GetEnumerator()){
        Write-Host "[DBFZ-CPU-1838] $($kv.Key)=$($kv.Value)"
        if(-not $kv.Value){throw "POST-AUDIT failed: $($kv.Key)"}
    }
    Write-Host "[DBFZ-CPU-1838] POST-AUDIT PASSED."
} finally { Stop-V1838Transcript $t }
