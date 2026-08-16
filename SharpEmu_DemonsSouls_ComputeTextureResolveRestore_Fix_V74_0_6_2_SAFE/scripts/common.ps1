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
        throw "[V74.0.6.2] Invalid repository root: $root"
    }

    return $root
}

function Get-PresenterPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.6.2] Missing VulkanVideoPresenter.cs: $p"
    }

    return $p
}

function Get-AgcPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Libs","Agc","AgcExports.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.6.2] Missing AgcExports.cs: $p"
    }

    return $p
}

function Get-MainPath([string]$Root){
    $p=[System.IO.Path]::Combine(
        $Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.cs")

    if(-not [System.IO.File]::Exists($p)){
        throw "[V74.0.6.2] Missing DirectExecutionBackend.cs: $p"
    }

    return $p
}

function Get-Utf8EncodingForExistingFile([string]$Path){
    $bytes=[System.IO.File]::ReadAllBytes($Path)

    $hasBom=
        $bytes.Length-ge 3 -and
        $bytes[0]-eq 0xEF -and
        $bytes[1]-eq 0xBB -and
        $bytes[2]-eq 0xBF

    return (New-Object System.Text.UTF8Encoding($hasBom))
}

function Find-LineIndexes {
    param(
        [string[]]$Lines,
        [string]$Needle
    )

    $result=New-Object System.Collections.Generic.List[int]

    for($i=0;$i-lt$Lines.Length;$i++){
        if($Lines[$i].IndexOf(
                $Needle,
                [System.StringComparison]::Ordinal)-ge 0){
            $result.Add($i)
        }
    }

    return $result.ToArray()
}

function Window-ContainsTrimmed {
    param(
        [string[]]$Lines,
        [int]$Start,
        [int]$Length,
        [string]$ExactTrimmed
    )

    $end=[Math]::Min(
        $Lines.Length,
        $Start+$Length)

    for($i=$Start;$i-lt$end;$i++){
        if($Lines[$i].Trim() -eq $ExactTrimmed){
            return $true
        }
    }

    return $false
}

function Get-ComputePhysicalLineState {
    param([string]$PresenterPath)

    $lines=[System.IO.File]::ReadAllLines($PresenterPath)

    $marker=
        "SHARPEMU_V73_20_COMPUTE_BINK_YUV_BINDING"

    $restore=
        "SHARPEMU_V74_0_6_2_COMPUTE_TEXTURE_RESOLVE_RESTORE"

    $markerIndexes=@(
        Find-LineIndexes $lines $marker
    )

    $restoreIndexes=@(
        Find-LineIndexes $lines $restore
    )

    $collapsed=$false
    $markerIndex=-1
    $windowHost=$false
    $windowFor=$false
    $windowAssign=$false
    $windowResolve=$false
    $windowNull=$false

    if($markerIndexes.Count-eq 1){
        $markerIndex=[int]$markerIndexes[0]
        $line=$lines[$markerIndex]

        $collapsed=
            $line.TrimStart().StartsWith("//") -and
            $line.Contains("var hostMovieTextures") -and
            $line.Contains("resources.Textures[index]") -and
            $line.Contains("ResolveTextureResource(texture)")

        $windowStart=$markerIndex
        $windowLength=80

        $windowHost=
            Window-ContainsTrimmed `
                $lines `
                $windowStart `
                $windowLength `
                "var hostMovieTextures = FindHostMovieTextureBindings(dispatch.Textures);"

        $windowFor=
            Window-ContainsTrimmed `
                $lines `
                $windowStart `
                $windowLength `
                "for (var index = 0; index < dispatch.Textures.Count; index++)"

        $windowAssign=
            Window-ContainsTrimmed `
                $lines `
                $windowStart `
                $windowLength `
                "resources.Textures[index] ="

        $windowResolve=
            Window-ContainsTrimmed `
                $lines `
                $windowStart `
                $windowLength `
                ": ResolveTextureResource(texture);"

        $windowNull=
            Window-ContainsTrimmed `
                $lines `
                $windowStart `
                $windowLength `
                "if (resources.Textures[index] is null)"
    }

    [pscustomobject]@{
        Lines=$lines
        MarkerCount=$markerIndexes.Count
        MarkerIndex=$markerIndex
        RestoreCount=$restoreIndexes.Count
        Collapsed=$collapsed
        HostExecutable=$windowHost
        ForExecutable=$windowFor
        AssignmentExecutable=$windowAssign
        ResolveExecutable=$windowResolve
        NullGuardExecutable=$windowNull
    }
}

function Invoke-DotNetChecked {
    param([string]$Root,[string[]]$Arguments)

    Push-Location $Root
    try{
        & dotnet @Arguments
        $rc=$LASTEXITCODE

        if($rc-ne 0){
            throw "[V74.0.6.2] dotnet failed with exit code $rc"
        }
    } finally {
        Pop-Location
    }
}
