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
        throw "[V74.0.7] Invalid repository root: $root"
    }

    return $root
}

function Get-PresenterPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,
        "src",
        "SharpEmu.Libs",
        "VideoOut",
        "VulkanVideoPresenter.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.7] Missing VulkanVideoPresenter.cs: $p"
    }

    return $p
}

function Get-PayloadPath {
    $packageRoot=[System.IO.Path]::GetFullPath(
        (Split-Path -Parent $PSScriptRoot).TrimEnd('\','/'))

    $p=[System.IO.Path]::Combine(
        $packageRoot,
        "payload",
        "VulkanVideoPresenter.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.7] Payload presenter missing: $p"
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
            throw "[V74.0.7] dotnet failed with exit code $rc"
        }
    } finally {
        Pop-Location
    }
}
