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
        throw "[V74.0.11.2] Invalid repository root: $root"
    }

    return $root
}

function Get-PresenterPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.11.2] Missing VulkanVideoPresenter.cs: $p"
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
            throw "[V74.0.11.2] dotnet failed with exit code $rc"
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
        throw "[V74.0.11.2] Missing NativeWorker source: $p"
    }
    return $p
}

function Get-PayloadNativeWorkerV74010 {
    $packageRoot=[System.IO.Path]::GetFullPath(
        (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))
    $p=[System.IO.Path]::Combine(
        $packageRoot,"payload","DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.11.2] Missing NativeWorker payload: $p"
    }
    return $p
}


function Get-PresenterPayloadV74011 {
    $packageRoot=[System.IO.Path]::GetFullPath(
        (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))
    $p=[System.IO.Path]::Combine(
        $packageRoot,"payload","VulkanVideoPresenter.cs")
    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.11.2] Missing presenter payload: $p"
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
        throw "[V74.0.11.2] Native-lane semantic verification failed: $($failed -join ', ')"
    }

    [pscustomobject]@{
        Passed=($failed.Count-eq 0)
        Failed=$failed
        Checks=$checks
    }
}
