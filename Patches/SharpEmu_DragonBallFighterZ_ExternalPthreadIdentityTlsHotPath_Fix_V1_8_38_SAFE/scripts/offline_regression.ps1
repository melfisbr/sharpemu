$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function New-DirectFixture([string]$nl) {
    $lines=@(
        "partial class DirectExecutionBackend",
        "{",
        "    // SHARPEMU_PTHREAD_SAFE_SPLIT_V1_8_27",
        "    // SHARPEMU_PTHREAD_HOT_KIND_PRECLASS_V1_8_34_1",
        "    private const byte PthreadHotKindNoneV1834 = 0;",
        "    private const byte PthreadHotKindIdentityV1834 = 1;",
        "    private const byte PthreadHotKindTlsGetV1834 = 2;",
        "    private const byte PthreadHotKindMutexV1834 = 3;",
        "    private static bool _pthreadIdentityTlsImportHotPathV1827Enabled=true;",
        "    private static bool _pthreadMutexImportHotPathV1827Enabled=false;",
        "    private static bool _pthreadImportHotPathThreadAnnouncedV1824;",
        "    private static ulong _currentExternalGuestThreadHandle;",
        "    private unsafe bool TryDispatchPthreadImportHotPathV1824(",
        "        CpuContext cpuContext, ImportStubEntry importStubEntry, nint argPackPtr, out ulong result)",
        "    {",
        "        result = 0;",
        "        var pthreadHotKindV1834 = importStubEntry.PthreadHotKind;",
        "        if (pthreadHotKindV1834 == PthreadHotKindNoneV1834) return false;",
        "        var guestThreadHandle = GuestThreadExecution.CurrentGuestThreadHandle;",
        "        if (guestThreadHandle == 0)",
        "        {",
        "            return false;",
        "        }",
        "        var nid = importStubEntry.Nid;",
        "        var handled = false;",
        "        switch (pthreadHotKindV1834)",
        "        {",
        "            case PthreadHotKindIdentityV1834:",
        "                result = guestThreadHandle;",
        "                handled = true;",
        "                break;",
        "            case PthreadHotKindTlsGetV1834:",
        "                var key = unchecked((int)*(ulong*)argPackPtr);",
        "                handled = KernelPthreadExtendedCompatExports.TryGetSpecificForBoundGuestThreadFastV1824(key, out result);",
        "                break;",
        "            case PthreadHotKindMutexV1834:",
        "                handled = false;",
        "                break;",
        "        }",
        "        if (handled && !_pthreadImportHotPathThreadAnnouncedV1824)",
        "        {",
        "            _pthreadImportHotPathThreadAnnouncedV1824 = true;",
        "        }",
        "        return handled;",
        "    }",
        "    private unsafe bool TryDispatchHotMemoryLeaf() => false;",
        "}"
    )
    return [string]::Join($nl,$lines)+$nl
}

function New-PthreadFixture([string]$nl) {
    $lines=@(
        "public static class KernelPthreadCompatExports",
        "{",
        "    private static void TracePthreadSelf(CpuContext ctx, ulong currentThreadHandle)",
        "    {",
        "    }",
        "}"
    )
    return [string]::Join($nl,$lines)+$nl
}

function New-PthreadExtFixture([string]$nl) {
    $lines=@(
        "public static class KernelPthreadExtendedCompatExports",
        "{",
        "    private static readonly ConcurrentDictionary<ulong, ConcurrentDictionary<int, ulong>> _threadLocalSpecific = new();",
        "    [ThreadStatic]",
        "    private static ulong _pthreadTlsFastThreadHandleV1824;",
        "    [ThreadStatic]",
        "    private static ConcurrentDictionary<int, ulong>? _pthreadTlsFastValuesV1824;",
        "    public static bool TryGetSpecificForBoundGuestThreadFastV1824(",
        "        int key, out ulong value)",
        "    {",
        "        value=0;",
        "        return false;",
        "    }",
        "}"
    )
    return [string]::Join($nl,$lines)+$nl
}

$variants=@("`n","`r`n")
foreach($nl in $variants){
    $d=New-DirectFixture $nl
    $p=New-PthreadFixture $nl
    $e=New-PthreadExtFixture $nl
    $pd=Patch-DirectImportsV1838 $d
    $pp=Patch-PthreadV1838 $p
    $pe=Patch-PthreadExtV1838 $e
    if(-not $pd.Contains("externalPthreadIdentityV1838")){throw "Direct regression missing recovery."}
    if(-not $pd.Contains("TryGetSpecificForThreadHandleFastV1838")){throw "Direct regression missing explicit TLS call."}
    if(-not $pp.Contains("GetCurrentExternalPthreadHandleFastV1838")){throw "Pthread bridge regression."}
    if(-not $pe.Contains("TryGetSpecificForThreadHandleFastV1838")){throw "PthreadExt regression."}
    if((Patch-DirectImportsV1838 $pd) -ne $pd){throw "Direct idempotence regression."}
    if((Patch-PthreadV1838 $pp) -ne $pp){throw "Pthread idempotence regression."}
    if((Patch-PthreadExtV1838 $pe) -ne $pe){throw "PthreadExt idempotence regression."}
}

$mixed=(New-DirectFixture "`n").Replace("        var guestThreadHandle = GuestThreadExecution.CurrentGuestThreadHandle;`n","        var guestThreadHandle = GuestThreadExecution.CurrentGuestThreadHandle;`r`n")
$pm=Patch-DirectImportsV1838 $mixed
if(-not $pm.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_IDENTITY_TLS_HOTPATH_V1_8_38")){throw "Mixed-EOL direct regression."}

Write-Host "[DBFZ-CPU-1838] LF/CRLF/MIXED STRUCTURAL+IDEMPOTENCE REGRESSION PASSED."
