Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Resolve-RepoRootV74017 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $RepositoryRoot=(Get-Location).Path
    }
    $root=[System.IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[System.IO.Path]::Combine($root,"src","SharpEmu.CLI","SharpEmu.CLI.csproj")
    if(-not [System.IO.File]::Exists($marker)){
        throw "[V74.0.17] Repository root invalid: $root"
    }
    return $root
}

function Get-PthreadPathV74017 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","Kernel","KernelPthreadCompatExports.cs")
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.17] Missing pthread source: $path"
    }
    return $path
}

function Get-AgcPathV74017 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Agc","AgcExports.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.17] Missing AGC source: $path"}
    return $path
}

function Get-PresenterPathV74017 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.17] Missing presenter source: $path"}
    return $path
}

function Get-NativeWorkerPathV74017 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.17] Missing NativeWorker source: $path"}
    return $path
}

function Get-HostMovieBridgePathV74017 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.17] Missing HostMovieBridge source: $path"}
    return $path
}

function Get-CSharpMethodSpanV74017 {
    param([string]$Text,[string]$Signature)
    $start=$Text.IndexOf($Signature,[System.StringComparison]::Ordinal)
    if($start -lt 0){
        return [pscustomobject]@{Start=-1;Length=0;Text=""}
    }
    if($Text.IndexOf($Signature,$start+$Signature.Length,[System.StringComparison]::Ordinal) -ge 0){
        throw "[V74.0.17] C# method signature is not unique: $Signature"
    }
    $open=$Text.IndexOf('{',$start)
    if($open -lt 0){throw "[V74.0.17] Opening brace missing after: $Signature"}
    $depth=0
    $end=-1
    for($index=$open;$index -lt $Text.Length;$index++){
        $character=$Text[$index]
        if($character -eq '{'){$depth++}
        elseif($character -eq '}'){
            $depth--
            if($depth -eq 0){$end=$index+1;break}
        }
    }
    if($end -lt 0){throw "[V74.0.17] Closing brace missing after: $Signature"}
    return [pscustomobject]@{
        Start=$start
        Length=$end-$start
        Text=$Text.Substring($start,$end-$start)
    }
}

function Get-PthreadOpaqueOwnerGateStateV74017 {
    param([string]$Text)
    $marker="SHARPEMU_V74_0_17_DEMONS_PTHREAD_OPAQUE_OWNER_GATE"
    $baseMarker="SHARPEMU_DBFZ_PTHREAD_OPAQUE_OWNER_SYNC_V1_4_5"
    $fieldAnchor="private static int _dbfzOpaqueOwnerTraceCount;"
    $lockSignature="private static int PthreadMutexLockCoreWithOpaqueOwnerSync("
    $unlockSignature="private static int PthreadMutexUnlockCoreWithOpaqueOwnerSync("

    if(-not $Text.Contains($baseMarker)){
        return [pscustomobject]@{State="MissingDbfzBaseline";Detail=$baseMarker}
    }
    if(([regex]::Matches($Text,[regex]::Escape($fieldAnchor))).Count -ne 1){
        return [pscustomobject]@{State="InvalidFieldAnchor";Detail=$fieldAnchor}
    }

    $lockSpan=Get-CSharpMethodSpanV74017 -Text $Text -Signature $lockSignature
    $unlockSpan=Get-CSharpMethodSpanV74017 -Text $Text -Signature $unlockSignature
    if($lockSpan.Start -lt 0 -or $unlockSpan.Start -lt 0){
        return [pscustomobject]@{State="MissingWrapperMethod";Detail="lock/unlock wrapper"}
    }

    if($Text.Contains($marker)){
        $required=@(
            "SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC",
            "_v74017OpaqueOwnerSyncEnabled",
            "ReadV74017OpaqueOwnerSyncEnabled",
            "_v74017OpaqueOwnerSyncEnabled -and result" # synthetic token replaced below for C# validation
        )
        # The final item above is a PowerShell-side sentinel only. Validate C# form explicitly.
        foreach($needle in $required[0..2]){
            if(-not $Text.Contains($needle)){
                return [pscustomobject]@{State="PartialApplied";Detail=$needle}
            }
        }
        $gatePattern='_v74017OpaqueOwnerSyncEnabled\s*&&\s*result\s*=='
        if(([regex]::Matches($lockSpan.Text,$gatePattern)).Count -ne 1 -or
           ([regex]::Matches($unlockSpan.Text,$gatePattern)).Count -ne 1){
            return [pscustomobject]@{State="PartialApplied";Detail="wrapper gate"}
        }
        return [pscustomobject]@{State="Applied";Detail="ok"}
    }

    $successIf='if\s*\(\s*result\s*==\s*\(int\)OrbisGen2Result\.ORBIS_GEN2_OK\s*\)'
    if(([regex]::Matches($lockSpan.Text,$successIf)).Count -ne 1 -or
       ([regex]::Matches($unlockSpan.Text,$successIf)).Count -ne 1){
        return [pscustomobject]@{State="UnsupportedWrapperShape";Detail="success if"}
    }
    return [pscustomobject]@{State="Ready";Detail="ok"}
}

function Add-PthreadOpaqueOwnerGateV74017 {
    param([string]$Text)
    $state=Get-PthreadOpaqueOwnerGateStateV74017 -Text $Text
    if($state.State -eq "Applied"){return $Text}
    if($state.State -ne "Ready"){
        throw "[V74.0.17] Pthread structural state rejected: $($state.State) / $($state.Detail)"
    }

    $newLine=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
    $fieldAnchor="private static int _dbfzOpaqueOwnerTraceCount;"
    $fieldIndex=$Text.IndexOf($fieldAnchor,[System.StringComparison]::Ordinal)
    $fieldEnd=$fieldIndex+$fieldAnchor.Length
    $insert=@(
        "",
        "    // SHARPEMU_V74_0_17_DEMONS_PTHREAD_OPAQUE_OWNER_GATE",
        "    // DBFZ V1.4.5 mirrors adaptive mutex ownership into an opaque guest",
        "    // pthread field. Keep that compatibility enabled by default, but let",
        "    // other titles opt out of the extra guest-memory work explicitly.",
        "    private static readonly bool _v74017OpaqueOwnerSyncEnabled =",
        "        ReadV74017OpaqueOwnerSyncEnabled();",
        "",
        "    private static bool ReadV74017OpaqueOwnerSyncEnabled()",
        "    {",
        '        var value = Environment.GetEnvironmentVariable("SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC");',
        "        var enabled =",
        '            !string.Equals(value, "0", StringComparison.OrdinalIgnoreCase) &&',
        '            !string.Equals(value, "false", StringComparison.OrdinalIgnoreCase) &&',
        '            !string.Equals(value, "off", StringComparison.OrdinalIgnoreCase);',
        "        if (value is not null)",
        "        {",
        "            Console.Error.WriteLine(",
        '                $"[V74.0.17][PTHREAD_FASTBOOT] opaque_owner_sync={(enabled ? "enabled" : "disabled")} default=enabled");',
        "        }",
        "        return enabled;",
        "    }"
    ) -join $newLine
    $Text=$Text.Substring(0,$fieldEnd)+$insert+$Text.Substring($fieldEnd)

    $successIf='if\s*\(\s*result\s*==\s*\(int\)OrbisGen2Result\.ORBIS_GEN2_OK\s*\)'
    foreach($signature in @(
        "private static int PthreadMutexLockCoreWithOpaqueOwnerSync(",
        "private static int PthreadMutexUnlockCoreWithOpaqueOwnerSync("
    )){
        $span=Get-CSharpMethodSpanV74017 -Text $Text -Signature $signature
        $matchList=@([regex]::Matches($span.Text,$successIf))
        if($matchList.Count -ne 1){
            throw "[V74.0.17] Wrapper success-if count=$($matchList.Count): $signature"
        }
        $match=$matchList[0]
        $replacement='if (_v74017OpaqueOwnerSyncEnabled && result == (int)OrbisGen2Result.ORBIS_GEN2_OK)'
        $method=$span.Text.Substring(0,$match.Index)+$replacement+$span.Text.Substring($match.Index+$match.Length)
        $Text=$Text.Substring(0,$span.Start)+$method+$Text.Substring($span.Start+$span.Length)
    }

    $finalState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $Text
    if($finalState.State -ne "Applied"){
        throw "[V74.0.17] Pthread post-transform validation failed: $($finalState.State) / $($finalState.Detail)"
    }
    return $Text
}

function Invoke-DotNetCheckedV74017 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try{
        & dotnet @Arguments
        if($LASTEXITCODE -ne 0){
            throw "[V74.0.17] dotnet failed with exit code $LASTEXITCODE"
        }
    }
    finally{Pop-Location}
}

function Sync-ReleaseRuntimeAssetsV74017 {
    param([string]$Root)
    $debug=[System.IO.Path]::Combine($Root,"artifacts","bin","Debug","net10.0","win-x64")
    $release=[System.IO.Path]::Combine($Root,"artifacts","bin","Release","net10.0","win-x64")
    if(-not [System.IO.Directory]::Exists($release)){return}
    $debugPlugins=[System.IO.Path]::Combine($debug,"plugins")
    $releasePlugins=[System.IO.Path]::Combine($release,"plugins")
    if([System.IO.Directory]::Exists($debugPlugins)){
        [System.IO.Directory]::CreateDirectory($releasePlugins)|Out-Null
        foreach($item in Get-ChildItem -LiteralPath $debugPlugins -Force){
            Copy-Item -LiteralPath $item.FullName -Destination $releasePlugins -Recurse -Force
        }
    }
    $cacheRel=[System.IO.Path]::Combine("user","pipeline_cache","PPSA01341","vulkan-pipeline-cache.bin")
    $debugCache=[System.IO.Path]::Combine($debug,$cacheRel)
    $releaseCache=[System.IO.Path]::Combine($release,$cacheRel)
    if([System.IO.File]::Exists($debugCache) -and -not [System.IO.File]::Exists($releaseCache)){
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($releaseCache))|Out-Null
        Copy-Item -LiteralPath $debugCache -Destination $releaseCache -Force
    }
}

function Get-DescendantProcessIdsV74017 {
    param([int]$RootProcessId)
    $result=New-Object 'System.Collections.Generic.List[int]'
    try{
        $rows=@(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
        $frontier=New-Object 'System.Collections.Generic.Queue[int]'
        $frontier.Enqueue($RootProcessId)
        while($frontier.Count -gt 0){
            $parentProcessId=$frontier.Dequeue()
            foreach($row in $rows){
                if([int]$row.ParentProcessId -eq $parentProcessId){
                    $childProcessId=[int]$row.ProcessId
                    if(-not $result.Contains($childProcessId)){
                        $result.Add($childProcessId)
                        $frontier.Enqueue($childProcessId)
                    }
                }
            }
        }
    }
    catch{}
    return @($result)
}

function Get-ProcessTreeSampleV74017 {
    param([int]$RootProcessId)
    $processIds=New-Object 'System.Collections.Generic.List[int]'
    $processIds.Add($RootProcessId)
    foreach($childProcessId in @(Get-DescendantProcessIdsV74017 -RootProcessId $RootProcessId)){
        if(-not $processIds.Contains($childProcessId)){$processIds.Add($childProcessId)}
    }
    [int64]$workingBytes=0
    [int64]$privateBytes=0
    [double]$cpuSeconds=0.0
    [int]$liveCount=0
    [int]$largestProcessId=0
    [int64]$largestPrivateBytes=0
    foreach($processIdValue in $processIds){
        try{
            $process=Get-Process -Id $processIdValue -ErrorAction Stop
            $workingBytes += [int64]$process.WorkingSet64
            $privateBytes += [int64]$process.PrivateMemorySize64
            if($null -ne $process.CPU){$cpuSeconds += [double]$process.CPU}
            $liveCount++
            if([int64]$process.PrivateMemorySize64 -gt $largestPrivateBytes){
                $largestPrivateBytes=[int64]$process.PrivateMemorySize64
                $largestProcessId=$processIdValue
            }
        }
        catch{}
    }
    return [pscustomobject]@{
        WorkingBytes=$workingBytes
        PrivateBytes=$privateBytes
        CpuSeconds=$cpuSeconds
        LiveCount=$liveCount
        LargestProcessId=$largestProcessId
    }
}

function Stop-ProcessTreeV74017 {
    param([int]$RootProcessId)
    $descendants=@(Get-DescendantProcessIdsV74017 -RootProcessId $RootProcessId)
    [array]::Reverse($descendants)
    foreach($processIdValue in $descendants){
        try{Stop-Process -Id $processIdValue -Force -ErrorAction Stop}catch{}
    }
    try{Stop-Process -Id $RootProcessId -Force -ErrorAction Stop}catch{}
}

function Read-SharedTextV74017 {
    param([string]$Path,[int]$Attempts=20,[int]$DelayMilliseconds=150)
    for($attempt=0;$attempt -lt $Attempts;$attempt++){
        try{
            if(-not [System.IO.File]::Exists($Path)){return ""}
            $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try{
                $reader=New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8,$true)
                try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
            }
            finally{$stream.Dispose()}
        }
        catch{
            if($attempt -ge ($Attempts-1)){throw}
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
    return ""
}

function Read-NewSharedChunkV74017 {
    param([string]$Path,[ref]$Offset)
    if(-not [System.IO.File]::Exists($Path)){return ""}
    try{
        $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        try{
            if($Offset.Value -gt $stream.Length){$Offset.Value=[int64]0}
            [void]$stream.Seek([int64]$Offset.Value,[System.IO.SeekOrigin]::Begin)
            $reader=New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8,$true,4096,$true)
            try{
                $text=$reader.ReadToEnd()
                $Offset.Value=$stream.Position
                return $text
            }
            finally{$reader.Dispose()}
        }
        finally{$stream.Dispose()}
    }
    catch{return ""}
}

function Bound-DeadlineV74017 {
    param([DateTime]$Candidate,[DateTime]$Absolute)
    if($Candidate -gt $Absolute){return $Absolute}
    return $Candidate
}
