Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Resolve-RepoRootV74014 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $RepositoryRoot=(Get-Location).Path
    }
    $root=[System.IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[System.IO.Path]::Combine($root,"src","SharpEmu.CLI","SharpEmu.CLI.csproj")
    if(-not [System.IO.File]::Exists($marker)){
        throw "[V74.0.14] Repository root invalid: $root"
    }
    return $root
}

function Get-NativeWorkerPathV74014 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.14] Missing NativeWorker source: $path"
    }
    return $path
}

function Get-PresenterPathV74014 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.14] Missing Vulkan presenter source: $path"
    }
    return $path
}

function Get-HostMovieBridgePathV74014 {
    param([string]$Root)
    $path=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs")
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.14] Missing HostMovieBridge source: $path"
    }
    return $path
}

function Get-NativeWorkerDeclarationV74014 {
    param([string]$Text)
    $pattern='(?m)^(?<lhs>\s*(?:private|internal|public|protected)?\s*(?:static\s+)?(?:readonly\s+|const\s+)?int\s+NativeWorkerMaxConcurrent\s*)=\s*(?<rhs>[^;\r\n]+)\s*;[ \t]*(?=\r?$)'
    $match=[regex]::Match($Text,$pattern)
    if(-not $match.Success){ return $null }
    return [pscustomobject]@{
        Match=$match
        Start=$match.Index
        Length=$match.Length
        Text=$match.Value
        Lhs=$match.Groups['lhs'].Value
        Rhs=$match.Groups['rhs'].Value.Trim()
        IsConst=($match.Value -match '\bconst\b')
    }
}

function Get-NativeWorkerLimiterStateV74014 {
    param([string]$Path)
    $text=[System.IO.File]::ReadAllText($Path)
    $decl=Get-NativeWorkerDeclarationV74014 -Text $text
    if($null -eq $decl){
        return [pscustomobject]@{
            Text=$text; Declaration=$null; State='MissingDeclaration'; DefaultCap=$null
        }
    }

    if($text.Contains('SHARPEMU_V74_0_14_DEMONS_RUNTIME_TBB_LIMIT')){
        return [pscustomobject]@{
            Text=$text; Declaration=$decl; State='V74014Applied'; DefaultCap=$null
        }
    }

    $hasGenericEnv=$text.Contains('Environment.GetEnvironmentVariable("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT")')
    if($hasGenericEnv -and ($decl.Rhs -match 'ReadNativeWorkerMaxConcurrent\s*\(')){
        return [pscustomobject]@{
            Text=$text; Declaration=$decl; State='ExistingEnvironmentReader'; DefaultCap=$null
        }
    }

    if($decl.Rhs -match '^\d+$'){
        $cap=[int]$decl.Rhs
        return [pscustomobject]@{
            Text=$text; Declaration=$decl; State='LiteralCap'; DefaultCap=$cap
        }
    }

    return [pscustomobject]@{
        Text=$text; Declaration=$decl; State='UnsupportedDeclaration'; DefaultCap=$null
    }
}

function Invoke-DotNetCheckedV74014 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try{
        & dotnet @Arguments
        if($LASTEXITCODE -ne 0){
            throw "[V74.0.14] dotnet failed with exit code $LASTEXITCODE"
        }
    }
    finally{
        Pop-Location
    }
}

function Sync-ReleaseRuntimeAssetsV74014 {
    param([string]$Root)
    $debug=[System.IO.Path]::Combine(
        $Root,"artifacts","bin","Debug","net10.0","win-x64")
    $release=[System.IO.Path]::Combine(
        $Root,"artifacts","bin","Release","net10.0","win-x64")
    if(-not [System.IO.Directory]::Exists($release)){return}

    $debugPlugins=[System.IO.Path]::Combine($debug,"plugins")
    $releasePlugins=[System.IO.Path]::Combine($release,"plugins")
    if([System.IO.Directory]::Exists($debugPlugins)){
        [System.IO.Directory]::CreateDirectory($releasePlugins)|Out-Null
        foreach($item in Get-ChildItem -LiteralPath $debugPlugins -Force){
            Copy-Item -LiteralPath $item.FullName -Destination $releasePlugins -Recurse -Force
        }
    }

    $cacheRel=[System.IO.Path]::Combine(
        "user","pipeline_cache","PPSA01341","vulkan-pipeline-cache.bin")
    $debugCache=[System.IO.Path]::Combine($debug,$cacheRel)
    $releaseCache=[System.IO.Path]::Combine($release,$cacheRel)
    if([System.IO.File]::Exists($debugCache) -and
       -not [System.IO.File]::Exists($releaseCache)){
        [System.IO.Directory]::CreateDirectory(
            [System.IO.Path]::GetDirectoryName($releaseCache))|Out-Null
        Copy-Item -LiteralPath $debugCache -Destination $releaseCache -Force
    }
}

function Test-CumulativeStateV74014 {
    param([string]$HostMovie,[string]$Presenter,[string]$Native)
    $hostText=[System.IO.File]::ReadAllText($HostMovie)
    $presenterText=[System.IO.File]::ReadAllText($Presenter)
    $nativeText=[System.IO.File]::ReadAllText($Native)

    $hostOk=
        $hostText.Contains("SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF") -and
        $hostText.Contains("startup_completion_shim_header_fallback")

    $presenterOk=
        $presenterText.Contains("SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE") -and
        $presenterText.Contains("SHARPEMU_RENDER_SCALE") -and
        $presenterText.Contains("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB") -and
        $presenterText.Contains("SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET")

    # Do not require the generic TBB environment reader here. DBFZ V1.8.18/1.8.19
    # intentionally rewrote the generic cap to a literal. V74.0.14 patches only
    # that declaration, preserving all later scheduler/ownership work.
    $nativeStructural=
        $nativeText.Contains("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE") -and
        $nativeText.Contains("SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT") -and
        ($null -ne (Get-NativeWorkerDeclarationV74014 -Text $nativeText))

    return [pscustomobject]@{
        Host=$hostOk
        Presenter=$presenterOk
        Native=$nativeStructural
    }
}

function Get-DescendantProcessIdsV74014 {
    param([int]$RootProcessId)

    $result=New-Object 'System.Collections.Generic.List[int]'
    try{
        $rows=@(
            Get-CimInstance Win32_Process -ErrorAction Stop |
            Select-Object ProcessId,ParentProcessId
        )
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
    catch{
        # Telemetry must never abort emulation.
    }

    return @($result)
}

function Get-ProcessTreeSampleV74014 {
    param([int]$RootProcessId)

    $processIds=New-Object 'System.Collections.Generic.List[int]'
    $processIds.Add($RootProcessId)
    foreach($childProcessId in @(Get-DescendantProcessIdsV74014 -RootProcessId $RootProcessId)){
        if(-not $processIds.Contains($childProcessId)){
            $processIds.Add($childProcessId)
        }
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
            if($null -ne $process.CPU){
                $cpuSeconds += [double]$process.CPU
            }
            $liveCount++
            if([int64]$process.PrivateMemorySize64 -gt $largestPrivateBytes){
                $largestPrivateBytes=[int64]$process.PrivateMemorySize64
                $largestProcessId=$processIdValue
            }
        }
        catch{
        }
    }

    return [pscustomobject]@{
        WorkingBytes=$workingBytes
        PrivateBytes=$privateBytes
        CpuSeconds=$cpuSeconds
        LiveCount=$liveCount
        LargestProcessId=$largestProcessId
        ProcessIds=@($processIds)
    }
}

function Stop-ProcessTreeV74014 {
    param([int]$RootProcessId)

    $descendants=@(Get-DescendantProcessIdsV74014 -RootProcessId $RootProcessId)
    [array]::Reverse($descendants)
    foreach($processIdValue in $descendants){
        try{
            Stop-Process -Id $processIdValue -Force -ErrorAction Stop
        }
        catch{
        }
    }

    try{
        Stop-Process -Id $RootProcessId -Force -ErrorAction Stop
    }
    catch{
    }
}

function Read-SharedTextV74014 {
    param([string]$Path,[int]$Attempts=20,[int]$DelayMilliseconds=150)

    for($attempt=0;$attempt -lt $Attempts;$attempt++){
        try{
            if(-not [System.IO.File]::Exists($Path)){return ""}
            $stream=[System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try{
                $reader=New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8,$true)
                try{
                    return $reader.ReadToEnd()
                }
                finally{
                    $reader.Dispose()
                }
            }
            finally{
                $stream.Dispose()
            }
        }
        catch{
            if($attempt -ge ($Attempts-1)){throw}
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    return ""
}

function Read-NewSharedChunkV74014 {
    param([string]$Path,[ref]$Offset)

    if(-not [System.IO.File]::Exists($Path)){return ""}
    try{
        $stream=[System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        try{
            if($Offset.Value -gt $stream.Length){
                $Offset.Value=[int64]0
            }
            [void]$stream.Seek([int64]$Offset.Value,[System.IO.SeekOrigin]::Begin)
            $reader=New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8,$true,4096,$true)
            try{
                $text=$reader.ReadToEnd()
                $Offset.Value=$stream.Position
                return $text
            }
            finally{
                $reader.Dispose()
            }
        }
        finally{
            $stream.Dispose()
        }
    }
    catch{
        return ""
    }
}

function Bound-DeadlineV74014 {
    param([DateTime]$Candidate,[DateTime]$Absolute)
    if($Candidate -gt $Absolute){return $Absolute}
    return $Candidate
}
