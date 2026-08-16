Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Resolve-RepoRoot {
    param([string]$RepositoryRoot)

    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $root=(Get-Location).Path
    } else {
        $root=[System.IO.Path]::GetFullPath(
            $RepositoryRoot.Trim().Trim('"').TrimEnd('\','/'))
    }

    if(-not [System.IO.Directory]::Exists(
            [System.IO.Path]::Combine($root,"src"))){
        throw "[V74.0.12] Invalid repository root: $root"
    }

    return $root
}

function Get-PresenterPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.12] Missing VulkanVideoPresenter.cs: $p"
    }

    return $p
}

function Invoke-DotNetChecked {
    param([string]$Root,[string[]]$Arguments)

    Push-Location $Root
    try{
        & dotnet @Arguments
        $rc=$LASTEXITCODE
        if($rc-ne 0){
            throw "[V74.0.12] dotnet failed with exit code $rc"
        }
    } finally {
        Pop-Location
    }
}

function Parse-DoubleInvariantOrCurrent {
    param([string]$Text)

    $value=0.0
    if([double]::TryParse(
            $Text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$value)){
        return $value
    }

    if([double]::TryParse(
            $Text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::CurrentCulture,
            [ref]$value)){
        return $value
    }

    return 0.0
}


function Get-NativeWorkerPathV74010 {
    param([string]$Root)
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Core","Cpu","Native",
        "DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.12] Missing NativeWorker source: $p"
    }
    return $p
}

function Get-PayloadNativeWorkerV74010 {
    $packageRoot=[System.IO.Path]::GetFullPath(
        (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))
    $p=[System.IO.Path]::Combine(
        $packageRoot,"payload","DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.12] Missing NativeWorker payload: $p"
    }
    return $p
}


function Get-PresenterPayloadV74011 {
    $packageRoot=[System.IO.Path]::GetFullPath(
        (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))
    $p=[System.IO.Path]::Combine(
        $packageRoot,"payload","VulkanVideoPresenter.cs")
    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.12] Missing presenter payload: $p"
    }
    return $p
}


function Test-NativeLaneSemanticV740111 {
    param(
        [string]$Path,
        [switch]$ThrowOnFailure
    )

    $text=[System.IO.File]::ReadAllText($Path)

    $checks=[ordered]@{
        marker=$text.Contains("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE")
        renderer_limit_symbol=$text.Contains("RendererResourceNativeWorkerMaxConcurrent")
        renderer_limiter=$text.Contains("_rendererResourceNativeWorkerRunLimiter")
        renderer_selector=$text.Contains("UsesRendererResourceNativeWorkerLane")
        renderer_env=$text.Contains("SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT")
        highgraphics=$text.Contains('"HighGraphics"')
        core_res=$text.Contains('"Core.Res."')
        nexus_event=$text.Contains('"NexusRevolution Event"')
        nexus_surveillance=$text.Contains('"NexusRevolution Surveillance"')
        no_managed_inline=$text.Contains("SHARPEMU_V74_0_3_4_NO_MANAGED_INLINE_FALLBACK")
        dedicated_generic=$text.Contains("SHARPEMU_V73_20_4_1_DEDICATED_GUEST_NATIVE_EXECUTOR")
        native_worker_gate=$text.Contains("_nativeWorkerRunLimiter")
        raw_executor=$text.Contains("NativeGuestExecutor")
    }

    $failed=@(
        $checks.GetEnumerator() |
        Where-Object{-not $_.Value} |
        ForEach-Object{$_.Key}
    )

    if($ThrowOnFailure -and $failed.Count-gt 0){
        throw "[V74.0.12] Native-lane semantic verification failed: $($failed -join ', ')"
    }

    [pscustomobject]@{
        Passed=($failed.Count-eq 0)
        Failed=$failed
        Checks=$checks
    }
}


function Get-HostMovieBridgePathV74012 {
    param([string]$Root)

    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.12] Missing HostMovieBridge.cs: $p"
    }

    return $p
}

function Test-StartupBinkHandoffStateV74012 {
    param([string]$Path)

    $text=[System.IO.File]::ReadAllText($Path)

    $installed=
        $text.Contains("SHARPEMU_V74_0_12_STARTUP_BINK_COMPLETION_HANDOFF") -and
        $text.Contains("IsOneShotStartupBinkV74012") -and
        $text.Contains("bink2.startup_completion_shim")

    $baseline=
        $text.Contains("internal static bool TryTakeOverGuestMovie(") -and
        $text.Contains("TryReadGuestCompletionShim(") -and
        $text.Contains("Keep the real header visible so the guest creates its movie surface") -and
        -not $installed

    [pscustomobject]@{
        Installed=$installed
        Baseline=$baseline
    }
}

function Install-StartupBinkHandoffV74012 {
    param([string]$Path)

    $text=[System.IO.File]::ReadAllText($Path)
    if($text.Contains("SHARPEMU_V74_0_12_STARTUP_BINK_COMPLETION_HANDOFF")){
        return
    }

    $startToken="    internal static bool TryTakeOverGuestMovie("
    $endToken="    internal static void NotifyGuestMovieClosed"

    $start=$text.IndexOf($startToken,[System.StringComparison]::Ordinal)
    if($start-lt 0){
        throw "[V74.0.12] TryTakeOverGuestMovie start anchor missing."
    }

    $end=$text.IndexOf(
        $endToken,
        $start,
        [System.StringComparison]::Ordinal)

    if($end-le$start){
        throw "[V74.0.12] TryTakeOverGuestMovie end anchor missing."
    }

    $oldRegion=$text.Substring($start,$end-$start)
    if(-not $oldRegion.Contains("return false;") -or
       -not $oldRegion.Contains("observed = ObserveGuestMovie(hostPath);")){
        throw "[V74.0.12] TryTakeOverGuestMovie baseline contract changed."
    }

    $replacement=@'
    // SHARPEMU_V74_0_12_STARTUP_BINK_COMPLETION_HANDOFF
    // The V74.0.11 direct fallback no longer depends on a guest Y/UV
    // descriptor. For the two one-shot startup movies, let the existing
    // BinkGuestCompletionShim hold the guest's NumFrames read until the host
    // has actually shown the real movie, then expose a one-frame completed
    // header so the statically linked guest Bink state machine can advance.
    // logo_intro_loop.bk2 is intentionally excluded: it is the title/Press
    // Start loop and must remain guest-controlled.
    private static bool IsOneShotStartupBinkV74012(string hostPath)
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
            string.Equals(
                name,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                name,
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase);
    }

    internal static bool TryTakeOverGuestMovie(
        string hostPath,
        out BinkGuestCompletionShim completionShim,
        out bool observed)
    {
        completionShim = default;
        observed = ObserveGuestMovie(hostPath);

        if (!observed ||
            !IsOneShotStartupBinkV74012(hostPath) ||
            !TryReadGuestCompletionShim(hostPath, out completionShim))
        {
            // Preserve the V73.20 guest-owned path for normal/loop/in-game
            // Binks so their real header and surfaces remain visible.
            completionShim = default;
            return false;
        }

        Console.Error.WriteLine(
            "[V74.0.12][BINK] bink2.startup_completion_shim " +
            "file='" + Path.GetFileName(hostPath) + "'");

        return true;
    }

'@

    if($text.Contains("`r`n")){
        $replacement=$replacement -replace "`n","`r`n"
    }

    $builder=[System.Text.StringBuilder]::new(
        $text.Length - $oldRegion.Length + $replacement.Length)

    [void]$builder.Append($text,0,$start)
    [void]$builder.Append($replacement)
    [void]$builder.Append($text,$end,$text.Length-$end)

    [System.IO.File]::WriteAllText(
        $Path,
        $builder.ToString(),
        [System.Text.UTF8Encoding]::new($false))
}
