$ErrorActionPreference = "Stop"

function Find-RepoRoot {
    $cursor = (Resolve-Path -LiteralPath $PSScriptRoot).Path
    for ($i = 0; $i -lt 12; $i++) {
        $checks = @(
            "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs",
            "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs",
            "src\SharpEmu.Libs\Kernel\KernelPthreadCompatExports.cs",
            "src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs",
            "src\SharpEmu.HLE\GuestThreadExecution.cs",
            "src\SharpEmu.Libs\Kernel\KernelAprCompatExports.cs",
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
        )
        $ok = $true
        foreach ($rel in $checks) {
            if (-not (Test-Path -LiteralPath (Join-Path $cursor $rel) -PathType Leaf)) { $ok = $false; break }
        }
        if ($ok) { return $cursor }
        $parent = Split-Path -Path $cursor -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    throw "SharpEmu repository root not found from package location '$PSScriptRoot'."
}

function Get-PatchesRoot {
    $repo = Find-RepoRoot
    $path = Join-Path $repo "Patches"
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Start-V1838Transcript {
    param([string]$Name,[switch]$NoTranscript)
    if ($NoTranscript) { return $null }
    $path = Join-Path (Get-PatchesRoot) $Name
    try { Start-Transcript -LiteralPath $path -Force | Out-Null; return $path } catch { return $null }
}
function Stop-V1838Transcript {
    param($Token)
    if ($null -ne $Token) { try { Stop-Transcript | Out-Null } catch {} }
}

function Get-Sha256Lower {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Read-TextRaw { param([string]$Path) return [IO.File]::ReadAllText($Path) }
function Write-TextPreserveUtf8Bom {
    param([string]$Path,[string]$Text)
    $bytes=[IO.File]::ReadAllBytes($Path)
    $bom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $enc=New-Object System.Text.UTF8Encoding($bom)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function Count-Literal {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count=0; $offset=0
    while ($true) {
        $i=$Text.IndexOf($Needle,$offset,[StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $count++; $offset=$i+$Needle.Length
    }
    return $count
}
function Get-LineMeta {
    param([string]$Text,[string]$Needle,[string]$Label)
    $count=Count-Literal $Text $Needle
    if ($count -ne 1) { throw "$Label expected exactly one anchor; found $count." }
    $idx=$Text.IndexOf($Needle,[StringComparison]::Ordinal)
    $lineStart=$idx
    while ($lineStart -gt 0 -and $Text[$lineStart-1] -ne "`n" -and $Text[$lineStart-1] -ne "`r") { $lineStart-- }
    $cursor=$idx+$Needle.Length
    while ($cursor -lt $Text.Length -and $Text[$cursor] -ne "`r" -and $Text[$cursor] -ne "`n") { $cursor++ }
    if ($cursor -ge $Text.Length) { throw "$Label has no line terminator." }
    if ($Text[$cursor] -eq "`r" -and ($cursor+1) -lt $Text.Length -and $Text[$cursor+1] -eq "`n") {
        return [pscustomobject]@{Index=$idx;LineStart=$lineStart;LineEnd=$cursor+2;NewLine="`r`n"}
    }
    return [pscustomobject]@{Index=$idx;LineStart=$lineStart;LineEnd=$cursor+1;NewLine=[string]$Text[$cursor]}
}
function Insert-LinesAfterUniqueLine {
    param([string]$Text,[string]$Needle,[string[]]$Lines=@(),[string]$Label)
    $m=Get-LineMeta $Text $Needle $Label
    $payload=if($Lines.Count -gt 0){[string]::Join($m.NewLine,$Lines)+$m.NewLine}else{""}
    return $Text.Substring(0,$m.LineEnd)+$payload+$Text.Substring($m.LineEnd)
}
function Insert-LinesBeforeUniqueLine {
    param([string]$Text,[string]$Needle,[string[]]$Lines=@(),[string]$Label)
    $m=Get-LineMeta $Text $Needle $Label
    $payload=if($Lines.Count -gt 0){[string]::Join($m.NewLine,$Lines)+$m.NewLine}else{""}
    return $Text.Substring(0,$m.LineStart)+$payload+$Text.Substring($m.LineStart)
}
function Replace-UniqueLine {
    param([string]$Text,[string]$Needle,[string[]]$Lines=@(),[string]$Label)
    $m=Get-LineMeta $Text $Needle $Label
    $payload=[string]::Join($m.NewLine,$Lines)+$m.NewLine
    return $Text.Substring(0,$m.LineStart)+$payload+$Text.Substring($m.LineEnd)
}
function Get-Region {
    param([string]$Text,[string]$StartNeedle,[string]$EndNeedle,[string]$Label)
    if ((Count-Literal $Text $StartNeedle) -ne 1) { throw "$Label start anchor is not unique." }
    $start=$Text.IndexOf($StartNeedle,[StringComparison]::Ordinal)
    $end=$Text.IndexOf($EndNeedle,$start,[StringComparison]::Ordinal)
    if ($end -lt 0) { throw "$Label end anchor not found after start." }
    return [pscustomobject]@{Start=$start;End=$end;Text=$Text.Substring($start,$end-$start)}
}
function Insert-LinesAfterUniqueLineInRegion {
    param([string]$Text,[string]$StartNeedle,[string]$EndNeedle,[string]$Needle,[string[]]$Lines=@(),[string]$Label)
    $r=Get-Region $Text $StartNeedle $EndNeedle $Label
    if ((Count-Literal $r.Text $Needle) -ne 1) { throw "$Label inner line expected once." }
    $patched=Insert-LinesAfterUniqueLine $r.Text $Needle $Lines ($Label+" inner")
    return $Text.Substring(0,$r.Start)+$patched+$Text.Substring($r.End)
}
function Insert-LinesBeforeUniqueLineInRegion {
    param([string]$Text,[string]$StartNeedle,[string]$EndNeedle,[string]$Needle,[string[]]$Lines=@(),[string]$Label)
    $r=Get-Region $Text $StartNeedle $EndNeedle $Label
    if ((Count-Literal $r.Text $Needle) -ne 1) { throw "$Label inner line expected once." }
    $patched=Insert-LinesBeforeUniqueLine $r.Text $Needle $Lines ($Label+" inner")
    return $Text.Substring(0,$r.Start)+$patched+$Text.Substring($r.End)
}
function Replace-UniqueLineInRegion {
    param([string]$Text,[string]$StartNeedle,[string]$EndNeedle,[string]$Needle,[string[]]$Lines=@(),[string]$Label)
    $r=Get-Region $Text $StartNeedle $EndNeedle $Label
    if ((Count-Literal $r.Text $Needle) -ne 1) { throw "$Label inner line expected once." }
    $patched=Replace-UniqueLine $r.Text $Needle $Lines ($Label+" inner")
    return $Text.Substring(0,$r.Start)+$patched+$Text.Substring($r.End)
}

function Get-V1838Paths {
    $repo=Find-RepoRoot
    return [ordered]@{
        Repo=$repo
        DirectImports=(Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs")
        DirectCore=(Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs")
        Pthread=(Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelPthreadCompatExports.cs")
        PthreadExt=(Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs")
        Guest=(Join-Path $repo "src\SharpEmu.HLE\GuestThreadExecution.cs")
        Apr=(Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelAprCompatExports.cs")
    }
}
function Read-V1838SourceSet {
    $p=Get-V1838Paths
    return [pscustomobject]@{
        Paths=$p
        DirectImports=Read-TextRaw $p.DirectImports
        DirectCore=Read-TextRaw $p.DirectCore
        Pthread=Read-TextRaw $p.Pthread
        PthreadExt=Read-TextRaw $p.PthreadExt
        Guest=Read-TextRaw $p.Guest
        Apr=Read-TextRaw $p.Apr
    }
}

function Get-V1838State {
    param([string]$DirectImports,[string]$Pthread,[string]$PthreadExt)
    $checks=@(
        $DirectImports.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_IDENTITY_TLS_HOTPATH_V1_8_38"),
        $DirectImports.Contains("externalPthreadIdentityV1838"),
        $DirectImports.Contains("TryGetSpecificForThreadHandleFastV1838"),
        $Pthread.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_HANDLE_BRIDGE_V1_8_38"),
        $Pthread.Contains("GetCurrentExternalPthreadHandleFastV1838"),
        $PthreadExt.Contains("SHARPEMU_DBFZ_EXPLICIT_TLS_HANDLE_FASTPATH_V1_8_38"),
        $PthreadExt.Contains("TryGetSpecificForThreadHandleFastV1838")
    )
    $n=@($checks|Where-Object{$_}).Count
    if($n -eq $checks.Count){return "Applied"}
    if($n -eq 0){return "Baseline"}
    return "Partial"
}

function Assert-V1838Prerequisites {
    param([pscustomobject]$S)
    $pthreadState="Unknown"
    if($S.Pthread.Contains("SHARPEMU_PTHREAD_MUTEX_RESOLVE_VALIDATED_CACHE_V1_8_36")){$pthreadState="V1.8.36"}
    elseif($S.Pthread.Contains("SHARPEMU_PTHREAD_OPAQUE_OWNER_RESOLVE_REUSE_V1_8_35")){$pthreadState="V1.8.35+"}
    Write-Host "[DBFZ-CPU-1838.1] PthreadOptimizationState=$pthreadState"
    $checks=[ordered]@{
        v1827_safe_split=$S.DirectImports.Contains("SHARPEMU_PTHREAD_SAFE_SPLIT_V1_8_27")
        v1834_1_kind_preclass=$S.DirectImports.Contains("SHARPEMU_PTHREAD_HOT_KIND_PRECLASS_V1_8_34_1")
        hotpath_method=$S.DirectImports.Contains("TryDispatchPthreadImportHotPathV1824(")
        explicit_tls_existing=$S.PthreadExt.Contains("TryGetSpecificForBoundGuestThreadFastV1824(")
        external_owner_field=$S.DirectCore.Contains("_currentExternalGuestThreadHandle")
        external_context_registration=$S.DirectCore.Contains("public void RegisterGuestThreadContext(ulong threadHandle, CpuContext context)")
        pthread_identity_state=$S.Pthread.Contains("KernelPthreadState.GetCurrentThreadHandle()")
        waiter_v1837=$S.Guest.Contains("SHARPEMU_DBFZ_COOPERATIVE_WAITER_LANE_RELEASE_V1_8_37")
        apr_v1837=$S.Apr.Contains("SHARPEMU_DBFZ_APR_COOPERATIVE_WAIT_V1_8_37")
        mutex_hotpath_default_off=$S.DirectImports.Contains('SHARPEMU_PTHREAD_MUTEX_IMPORT_HOTPATH')
    }
    foreach($kv in $checks.GetEnumerator()){
        Write-Host "[DBFZ-CPU-1838.1] prerequisite_$($kv.Key)=$($kv.Value)"
        if(-not $kv.Value){throw "Prerequisite failed: $($kv.Key)"}
    }
}

function Patch-PthreadV1838 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_HANDLE_BRIDGE_V1_8_38")){return $Text}
    return Insert-LinesBeforeUniqueLine $Text `
        "private static void TracePthreadSelf(CpuContext ctx, ulong currentThreadHandle)" @(
            "    // SHARPEMU_DBFZ_EXTERNAL_PTHREAD_HANDLE_BRIDGE_V1_8_38",
            "    // The top-level raw guest executor is not a scheduler-owned pthread, but",
            "    // KernelPthreadState already assigns it a stable synthetic pthread handle.",
            "    // Expose that existing identity to the import dispatcher without changing",
            "    // GuestThreadExecution.IsGuestThread or cooperative-wait ownership.",
            "    public static ulong GetCurrentExternalPthreadHandleFastV1838() =>",
            "        KernelPthreadState.GetCurrentThreadHandle();",
            ""
        ) "external pthread handle bridge"
}

function Patch-PthreadExtV1838 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_DBFZ_EXPLICIT_TLS_HANDLE_FASTPATH_V1_8_38")){return $Text}
    return Insert-LinesBeforeUniqueLine $Text `
        "public static bool TryGetSpecificForBoundGuestThreadFastV1824(" @(
            "    // SHARPEMU_DBFZ_EXPLICIT_TLS_HANDLE_FASTPATH_V1_8_38",
            "    // Same dictionary/cache semantics as V1.8.24, but accepts the already",
            "    // validated pthread identity explicitly so the root/external executor",
            "    // does not need to masquerade as a scheduler-owned guest pthread.",
            "    public static bool TryGetSpecificForThreadHandleFastV1838(",
            "        int key,",
            "        ulong currentThreadHandle,",
            "        out ulong value)",
            "    {",
            "        value = 0;",
            "        if (currentThreadHandle == 0)",
            "        {",
            "            return false;",
            "        }",
            "",
            "        ConcurrentDictionary<int, ulong>? values;",
            "        if (_pthreadTlsFastThreadHandleV1824 == currentThreadHandle)",
            "        {",
            "            values = _pthreadTlsFastValuesV1824;",
            "        }",
            "        else",
            "        {",
            "            _threadLocalSpecific.TryGetValue(currentThreadHandle, out values);",
            "            _pthreadTlsFastThreadHandleV1824 = currentThreadHandle;",
            "            _pthreadTlsFastValuesV1824 = values;",
            "        }",
            "",
            "        if (values is not null &&",
            "            values.TryGetValue(key, out var storedValue))",
            "        {",
            "            value = storedValue;",
            "        }",
            "",
            "        return true;",
            "    }",
            ""
        ) "explicit TLS handle helper"
}

function Patch-DirectImportsV1838 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_IDENTITY_TLS_HOTPATH_V1_8_38")){return $Text}
    if(-not $Text.Contains("SHARPEMU_PTHREAD_HOT_KIND_PRECLASS_V1_8_34_1")){throw "V1.8.34.1 hot-kind prerequisite missing."}

    $start="private unsafe bool TryDispatchPthreadImportHotPathV1824("
    $end="private unsafe bool TryDispatchHotMemoryLeaf("

    $Text=Insert-LinesBeforeUniqueLine $Text $start @(
        "    // SHARPEMU_DBFZ_EXTERNAL_PTHREAD_IDENTITY_TLS_HOTPATH_V1_8_38",
        "    private static readonly bool _traceExternalPthreadHotpathV1838 =",
        '        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_EXTERNAL_PTHREAD_TRACE"), "1", StringComparison.Ordinal);',
        "",
        "    [ThreadStatic]",
        "    private static long _externalPthreadHotpathCountV1838;",
        ""
    ) "external pthread hotpath fields"

    $Text=Insert-LinesAfterUniqueLineInRegion $Text $start $end `
        "var guestThreadHandle = GuestThreadExecution.CurrentGuestThreadHandle;" @(
            "        var externalPthreadIdentityV1838 = false;",
            "        if (guestThreadHandle == 0 &&",
            "            (pthreadHotKindV1834 == PthreadHotKindIdentityV1834 ||",
            "             pthreadHotKindV1834 == PthreadHotKindTlsGetV1834))",
            "        {",
            "            guestThreadHandle = _currentExternalGuestThreadHandle;",
            "            if (guestThreadHandle == 0)",
            "            {",
            "                guestThreadHandle = KernelPthreadCompatExports.GetCurrentExternalPthreadHandleFastV1838();",
            "                if (guestThreadHandle != 0)",
            "                {",
            "                    RegisterGuestThreadContext(guestThreadHandle, cpuContext);",
            "                }",
            "            }",
            "            externalPthreadIdentityV1838 = guestThreadHandle != 0;",
            "        }"
        ) "external pthread identity recovery"

    $Text=Replace-UniqueLineInRegion $Text $start $end `
        "handled = KernelPthreadExtendedCompatExports.TryGetSpecificForBoundGuestThreadFastV1824(key, out result);" @(
            "                handled = KernelPthreadExtendedCompatExports.TryGetSpecificForThreadHandleFastV1838(",
            "                    key,",
            "                    guestThreadHandle,",
            "                    out result);"
        ) "explicit TLS handle call"

    $Text=Insert-LinesBeforeUniqueLineInRegion $Text $start $end `
        "if (handled && !_pthreadImportHotPathThreadAnnouncedV1824)" @(
            "        if (handled && externalPthreadIdentityV1838 && _traceExternalPthreadHotpathV1838)",
            "        {",
            "            var externalCountV1838 = ++_externalPthreadHotpathCountV1838;",
            "            if (externalCountV1838 <= 32 ||",
            "                (externalCountV1838 & (externalCountV1838 - 1)) == 0)",
            "            {",
            "                Console.Error.WriteLine(",
            '                    $"[DBFZ-CPU-1838.1] external_identity_tls_hotpath n={externalCountV1838} " +',
            '                    $"guest=0x{guestThreadHandle:X16} kind={pthreadHotKindV1834} nid={nid}");',
            "            }",
            "        }",
            ""
        ) "external hotpath trace"
    return $Text
}

function Patch-AllV1838 {
    param([pscustomobject]$S)
    return [pscustomobject]@{
        DirectImports=Patch-DirectImportsV1838 $S.DirectImports
        Pthread=Patch-PthreadV1838 $S.Pthread
        PthreadExt=Patch-PthreadExtV1838 $S.PthreadExt
    }
}

function Resolve-SharpEmuExecutable {
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    $candidates = @(
        (Join-Path $RepositoryRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
        (Join-Path $RepositoryRoot 'artifacts\bin\Debug\net10.0\SharpEmu.exe'),
        (Join-Path $RepositoryRoot 'src\SharpEmu.CLI\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
        (Join-Path $RepositoryRoot 'src\SharpEmu.CLI\bin\Debug\net10.0\SharpEmu.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw "SharpEmu.exe not found."
}
