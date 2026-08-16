. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$target=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs"
$t=Get-Content -LiteralPath $target -Raw

$backup=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_PthreadTlsHotPath_V1_8_20_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $target -Destination (Join-Path $backup "KernelPthreadExtendedCompatExports.cs") -Force

try {
    if(-not $t.Contains('SHARPEMU_DBFZ_PTHREAD_TLS_HOTPATH_V1_8_20')){
        $getSig='public static int PosixPthreadGetspecific(CpuContext ctx)'
        $get=Find-MethodBlock -Text $t -Signature $getSig
        if($null -eq $get){throw "getspecific method not found"}

        $fields=@'
    // SHARPEMU_DBFZ_PTHREAD_TLS_HOTPATH_V1_8_20
    // GuestExecutionRunner keeps one host thread per guest pthread. Cache only
    // the per-thread values dictionary reference; individual key values remain
    // authoritative in ConcurrentDictionary, so key_delete/setspecific semantics
    // are preserved without a global lookup on every getspecific call.
    [ThreadStatic]
    private static ulong _pthreadTlsFastThreadHandle;

    [ThreadStatic]
    private static ConcurrentDictionary<int, ulong>? _pthreadTlsFastValues;

'@
        $t=$t.Insert($get.Start,$fields)

        # Re-find after insertion.
        $get=Find-MethodBlock -Text $t -Signature $getSig
        $newGet=@'
public static int PosixPthreadGetspecific(CpuContext ctx)
    {
        var key = unchecked((int)ctx[CpuRegister.Rdi]);
        var currentThreadHandle = KernelPthreadState.GetCurrentThreadHandle();

        ConcurrentDictionary<int, ulong>? values;
        if (_pthreadTlsFastThreadHandle == currentThreadHandle)
        {
            values = _pthreadTlsFastValues;
        }
        else
        {
            _threadLocalSpecific.TryGetValue(currentThreadHandle, out values);
            _pthreadTlsFastThreadHandle = currentThreadHandle;
            _pthreadTlsFastValues = values;
        }

        ulong value = 0;
        if (values is not null &&
            values.TryGetValue(key, out var storedValue))
        {
            value = storedValue;
        }

        ctx[CpuRegister.Rax] = value;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
'@
        $t=$t.Remove($get.Start,$get.End-$get.Start).Insert($get.Start,$newGet)

        # Update setspecific cache after GetOrAdd, without replacing its ABI logic.
        $set=Find-MethodBlock -Text $t -Signature 'public static int PosixPthreadSetspecific(CpuContext ctx)'
        if($null -eq $set){throw "setspecific method not found"}
        $old=@'
        var values = _threadLocalSpecific.GetOrAdd(
            currentThreadHandle,
            static _ => new ConcurrentDictionary<int, ulong>());
        values[key] = value;
'@
        $new=@'
        var values = _threadLocalSpecific.GetOrAdd(
            currentThreadHandle,
            static _ => new ConcurrentDictionary<int, ulong>());
        _pthreadTlsFastThreadHandle = currentThreadHandle;
        _pthreadTlsFastValues = values;
        values[key] = value;
'@
        $setText=$set.Text
        if(-not $setText.Contains($old)){throw "setspecific GetOrAdd anchor changed"}
        $setText=$setText.Replace($old,$new)
        $t=$t.Remove($set.Start,$set.End-$set.Start).Insert($set.Start,$setText)

        # Clear the thread-static reference when destructors remove this thread.
        $des=Find-MethodBlock -Text $t -Signature 'public static void RunThreadLocalDestructors(CpuContext ctx)'
        if($null -eq $des){throw "destructor method not found"}
        $oldDes='_threadLocalSpecific.TryRemove(threadHandle, out _);'
        $newDes=@'
_threadLocalSpecific.TryRemove(threadHandle, out _);
        if (_pthreadTlsFastThreadHandle == threadHandle)
        {
            _pthreadTlsFastThreadHandle = 0;
            _pthreadTlsFastValues = null;
        }
'@
        $desText=$des.Text
        if(-not $desText.Contains($oldDes)){throw "destructor removal anchor changed"}
        $desText=$desText.Replace($oldDes,$newDes)
        $t=$t.Remove($des.Start,$des.End-$des.Start).Insert($des.Start,$desText)

        Set-Content -LiteralPath $target -Value $t -Encoding utf8
        Write-Host "[DBFZ-TLS-1820] Installed pthread TLS dictionary hot-path cache."
    } else {
        Write-Host "[DBFZ-TLS-1820] Source already applied; build only."
    }

    Push-Location $repo
    try {
        dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0){throw "dotnet build failed with exit code $LASTEXITCODE"}
    } finally {Pop-Location}
} catch {
    Copy-Item -LiteralPath (Join-Path $backup "KernelPthreadExtendedCompatExports.cs") -Destination $target -Force
    Write-Host "[DBFZ-TLS-1820] Source restored after patch/build failure."
    throw
}
Write-Host "[DBFZ-TLS-1820] BUILD PASSED. Backup: $backup"
