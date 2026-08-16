Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Resolve-RepoRoot {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $RepositoryRoot=(Get-Location).Path
    }
    $root=[System.IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[System.IO.Path]::Combine($root,"src","SharpEmu.CLI","SharpEmu.CLI.csproj")
    if(-not [System.IO.File]::Exists($marker)){
        throw "[V74.0.13.1] Repository root invalid: $root"
    }
    return $root
}

function Get-HostMovieBridgePathV74013 {
    param([string]$Root)
    $p=[System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs")
    if(-not [System.IO.File]::Exists($p)){throw "[V74.0.13.1] Missing HostMovieBridge.cs: $p"}
    return $p
}

function Get-PresenterPathV74013 {
    param([string]$Root)
    $p=[System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")
    if(-not [System.IO.File]::Exists($p)){throw "[V74.0.13.1] Missing VulkanVideoPresenter.cs: $p"}
    return $p
}

function Get-NativeWorkerPathV74013 {
    param([string]$Root)
    $p=[System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($p)){throw "[V74.0.13.1] Missing DirectExecutionBackend.NativeWorker.cs: $p"}
    return $p
}

function Invoke-DotNetChecked {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try{
        & dotnet @Arguments
        if($LASTEXITCODE-ne 0){throw "dotnet failed with exit code $LASTEXITCODE"}
    } finally { Pop-Location }
}

function Test-V74013State {
    param([string]$HostMovie,[string]$Presenter,[string]$Native)
    $host=[System.IO.File]::ReadAllText($HostMovie)
    $presenterText=[System.IO.File]::ReadAllText($Presenter)
    $nativeText=[System.IO.File]::ReadAllText($Native)
    $v12=$host.Contains("SHARPEMU_V74_0_12_STARTUP_BINK_COMPLETION_HANDOFF") -and
         $host.Contains("bink2.startup_completion_shim")
    $v13=$host.Contains("SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF") -and
         $host.Contains("startup_completion_shim_header_fallback")
    $presenterOk=$presenterText.Contains("SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE") -and
                 $presenterText.Contains("SHARPEMU_RENDER_SCALE") -and
                 $presenterText.Contains("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB") -and
                 $presenterText.Contains("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB")
    $nativeOk=$nativeText.Contains("SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT") -and
              $nativeText.Contains("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT")
    return [pscustomobject]@{V12=$v12;V13=$v13;Presenter=$presenterOk;Native=$nativeOk}
}

function Install-RobustStartupHandoffV74013 {
    param([string]$Path)
    $text=[System.IO.File]::ReadAllText($Path)
    if($text.Contains("SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF")){return}

    $startToken="    // SHARPEMU_V74_0_12_STARTUP_BINK_COMPLETION_HANDOFF"
    $endToken="    internal static void NotifyGuestMovieClosed"
    $start=$text.IndexOf($startToken,[System.StringComparison]::Ordinal)
    if($start-lt 0){throw "[V74.0.13.1] V74.0.12 HostMovieBridge start anchor missing."}
    $end=$text.IndexOf($endToken,$start,[System.StringComparison]::Ordinal)
    if($end-le$start){throw "[V74.0.13.1] HostMovieBridge end anchor missing."}
    $oldRegion=$text.Substring($start,$end-$start)
    if(-not $oldRegion.Contains("TryTakeOverGuestMovie(") -or
       -not $oldRegion.Contains("TryReadGuestCompletionShim(hostPath, out completionShim)")){
        throw "[V74.0.13.1] V74.0.12 takeover region changed; refusing blind patch."
    }

    $replacement=@'
    // SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF
    // V74.0.12 required the precise Bink frame-index parser before it could
    // expose the one-frame completion header. The measured V74.0.12 run showed
    // handoff=0 even though the first startup movie was visibly presented.
    // Keep the precise path first, then fall back to the validated 16-byte KB2
    // core header. The fallback changes only NumFrames=1 and preserves the
    // movie's original file-size and largest-frame fields, so it cannot invent
    // a frame offset. It is limited to the two one-shot Demon's Souls startup
    // movies and remains opt-out through SHARPEMU_BINK_STARTUP_COMPLETION_SHIM=0.
    private static bool IsOneShotStartupBinkV74013(string hostPath)
    {
        if (string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_STARTUP_COMPLETION_SHIM"),
                "0",
                StringComparison.Ordinal))
        {
            return false;
        }

        var name = Path.GetFileName(hostPath);
        return
            string.Equals(name, "ps_studios_logo.bk2", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(name, "logo_intro.bk2", StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryReadGuestCompletionShimHeaderFallbackV74013(
        string hostPath,
        out BinkGuestCompletionShim completionShim)
    {
        completionShim = default;
        Span<byte> header = stackalloc byte[16];
        try
        {
            using var stream = new FileStream(
                hostPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            stream.ReadExactly(header);
            if (!header[..3].SequenceEqual("KB2"u8))
            {
                return false;
            }

            var fileSizeMinusHeader =
                BinaryPrimitives.ReadUInt32LittleEndian(header[4..8]);
            var frameCount =
                BinaryPrimitives.ReadUInt32LittleEndian(header[8..12]);
            var largestFrameSize =
                BinaryPrimitives.ReadUInt32LittleEndian(header[12..16]);
            if (frameCount < 2 ||
                fileSizeMinusHeader == 0 ||
                largestFrameSize == 0)
            {
                return false;
            }

            completionShim = new BinkGuestCompletionShim(
                fileSizeMinusHeader,
                largestFrameSize);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or EndOfStreamException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    internal static bool TryTakeOverGuestMovie(
        string hostPath,
        out BinkGuestCompletionShim completionShim,
        out bool observed)
    {
        completionShim = default;
        observed = ObserveGuestMovie(hostPath);

        if (!observed || !IsOneShotStartupBinkV74013(hostPath))
        {
            return false;
        }

        var precise = TryReadGuestCompletionShim(hostPath, out completionShim);
        var headerFallback = false;
        if (!precise)
        {
            headerFallback = TryReadGuestCompletionShimHeaderFallbackV74013(
                hostPath,
                out completionShim);
            if (!headerFallback)
            {
                completionShim = default;
                Console.Error.WriteLine(
                    "[V74.0.13.1][BINK] startup_completion_shim_unavailable file='" +
                    Path.GetFileName(hostPath) + "'");
                return false;
            }
        }

        Console.Error.WriteLine(
            precise
                ? "[V74.0.13.1][BINK] bink2.startup_completion_shim mode=precise file='" +
                    Path.GetFileName(hostPath) + "'"
                : "[V74.0.13.1][BINK] bink2.startup_completion_shim_header_fallback file='" +
                    Path.GetFileName(hostPath) + "'");
        return true;
    }

'@
    if($text.Contains("`r`n")){$replacement=$replacement -replace "`n","`r`n"}
    $builder=[System.Text.StringBuilder]::new($text.Length-$oldRegion.Length+$replacement.Length)
    [void]$builder.Append($text,0,$start)
    [void]$builder.Append($replacement)
    [void]$builder.Append($text,$end,$text.Length-$end)
    [System.IO.File]::WriteAllText($Path,$builder.ToString(),[System.Text.UTF8Encoding]::new($false))
}

function Sync-ReleaseRuntimeAssetsV74013 {
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
