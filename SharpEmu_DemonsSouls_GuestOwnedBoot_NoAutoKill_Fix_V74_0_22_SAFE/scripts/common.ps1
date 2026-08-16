Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Resolve-RepoRootV74022 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){$RepositoryRoot=(Get-Location).Path}
    $repoRoot=[System.IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[System.IO.Path]::Combine($repoRoot,"src","SharpEmu.CLI","SharpEmu.CLI.csproj")
    if(-not [System.IO.File]::Exists($marker)){throw "[V74.0.22] Repository root invalid: $repoRoot"}
    return $repoRoot
}

function Get-CpuDispatcherPathV74022 { param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","CpuDispatcher.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.22] Missing CpuDispatcher.cs: $path"}
    return $path
}
function Get-DirectBackendPathV74022 { param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.22] Missing DirectExecutionBackend.cs: $path"}
    return $path
}
function Get-KernelExportsPathV74022 { param([string]$Root)
    $path=[System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Kernel","KernelExports.cs")
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.22] Missing KernelExports.cs: $path"}
    return $path
}
function Get-HostMovieBridgePathV74022 { param([string]$Root)
    return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs")
}

function Get-CSharpMethodSpanV74022 {
    param([string]$Text,[string]$Signature)
    $start=$Text.IndexOf($Signature,[StringComparison]::Ordinal)
    if($start -lt 0){throw "[V74.0.22] C# method signature missing: $Signature"}
    $second=$Text.IndexOf($Signature,$start+$Signature.Length,[StringComparison]::Ordinal)
    if($second -ge 0){throw "[V74.0.22] C# method signature not unique: $Signature"}
    $open=$Text.IndexOf('{',$start)
    if($open -lt 0){throw "[V74.0.22] Opening brace missing after: $Signature"}
    $depth=0
    $end=-1
    for($charIndex=$open;$charIndex -lt $Text.Length;$charIndex++){
        $ch=$Text[$charIndex]
        if($ch -eq '{'){$depth++}
        elseif($ch -eq '}'){
            $depth--
            if($depth -eq 0){$end=$charIndex+1;break}
        }
    }
    if($end -lt 0){throw "[V74.0.22] Closing brace missing after: $Signature"}
    return [pscustomobject]@{Start=$start;End=$end;Text=$Text.Substring($start,$end-$start)}
}

function Replace-CSharpMethodV74022 {
    param([string]$Text,[string]$Signature,[string]$Replacement)
    $span=Get-CSharpMethodSpanV74022 -Text $Text -Signature $Signature
    return $Text.Substring(0,$span.Start)+$Replacement.TrimEnd()+$Text.Substring($span.End)
}

function Get-EntryAbiStateV74022 {
    param([string]$Text)
    $applied=$Text.Contains("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI") -and
        $Text.Contains("const ulong entryParamsSize = 0x118;") -and
        $Text.Contains("const int maxArguments = 33;") -and
        $Text.Contains("entryParamsAddress + entryAddressOffset, entryPoint") -and
        $Text.Contains("programExitHandlerStubAddress, entryPoint")
    if($applied){return "Applied"}
    $baseline=$Text.Contains("const ulong entryParamsSize = 0x20;") -and
        $Text.Contains("var arguments = new List<string>(3)") -and
        $Text.Contains("arguments.AddRange(compatibilityArguments.Take(2));") -and
        $Text.Contains("InitializeProcessEntryFrame(context, processImageName, programExitHandlerStubAddress)")
    if($baseline){return "Baseline"}
    return "Unknown"
}

function Get-InitEnvStateV74022 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC")){return "Applied"}
    $span=Get-CSharpMethodSpanV74022 -Text $Text -Signature "public static int InitEnv(CpuContext ctx)"
    if($span.Text.Contains("ctx[CpuRegister.Rax] = 0;") -and -not $span.Text.Contains("TryReadUInt64")){return "Baseline"}
    return "Unknown"
}

function Get-LleInitEnvStateV74022 {
    param([string]$Text)
    if($Text.Contains("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE") -and $Text.Contains('Environment.GetEnvironmentVariable("SHARPEMU_LLE_INIT_ENV")')){return "Applied"}
    $span=Get-CSharpMethodSpanV74022 -Text $Text -Signature "private static bool IsSafeLleLibcExport(string exportName)"
    if($span.Text.Contains('"memcpy" or') -and -not $span.Text.Contains('"_init_env"')){return "Baseline"}
    return "Unknown"
}

function Invoke-DotNetCheckedV74022 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try{
        & dotnet @Arguments
        if($LASTEXITCODE -ne 0){throw "[V74.0.22] dotnet failed with exit code $LASTEXITCODE"}
    } finally {Pop-Location}
}

function Sync-ReleaseRuntimeAssetsV74022 {
    param([string]$Root)
    $debugRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Debug","net10.0","win-x64")
    $releaseRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Release","net10.0","win-x64")
    if(-not [System.IO.Directory]::Exists($releaseRoot)){return}
    foreach($assetName in @("plugins","pipeline_cache")){
        $source=[System.IO.Path]::Combine($debugRoot,$assetName)
        $destination=[System.IO.Path]::Combine($releaseRoot,$assetName)
        if([System.IO.Directory]::Exists($source)){
            if(-not [System.IO.Directory]::Exists($destination)){[System.IO.Directory]::CreateDirectory($destination)|Out-Null}
            Copy-Item -Path ([System.IO.Path]::Combine($source,"*")) -Destination $destination -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV74022 {
    param([string]$Path)
    if(-not [System.IO.File]::Exists($Path)){return ""}
    for($attempt=0;$attempt -lt 5;$attempt++){
        try{
            $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try{
                $reader=[System.IO.StreamReader]::new($stream,[System.Text.Encoding]::UTF8,$true,65536,$false)
                try{return $reader.ReadToEnd()} finally {$reader.Dispose()}
            } finally {$stream.Dispose()}
        } catch {Start-Sleep -Milliseconds 100}
    }
    return ""
}

function Get-DescendantProcessIdsV74022 {
    param([int]$ParentId)
    $result=New-Object 'System.Collections.Generic.List[int]'
    $queue=New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while($queue.Count -gt 0){
        $currentId=$queue.Dequeue()
        $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach($childProcess in $children){
            $childId=[int]$childProcess.ProcessId
            if(-not $result.Contains($childId)){$result.Add($childId);$queue.Enqueue($childId)}
        }
    }
    return @($result)
}

function Stop-ProcessTreeV74022 {
    param([int]$RootId)
    $descendants=@(Get-DescendantProcessIdsV74022 -ParentId $RootId)
    [array]::Reverse($descendants)
    foreach($processIdValue in $descendants){Stop-Process -Id $processIdValue -Force -ErrorAction SilentlyContinue}
    Stop-Process -Id $RootId -Force -ErrorAction SilentlyContinue
}
