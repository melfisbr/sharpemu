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
        throw "[V74.0.10] Invalid repository root: $root"
    }

    return $root
}

function Get-PresenterPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.10] Missing VulkanVideoPresenter.cs: $p"
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
            throw "[V74.0.10] dotnet failed with exit code $rc"
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
        throw "[V74.0.10] Missing NativeWorker source: $p"
    }
    return $p
}

function Get-PayloadNativeWorkerV74010 {
    $packageRoot=[System.IO.Path]::GetFullPath(
        (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))
    $p=[System.IO.Path]::Combine(
        $packageRoot,"payload","DirectExecutionBackend.NativeWorker.cs")
    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.10] Missing NativeWorker payload: $p"
    }
    return $p
}
