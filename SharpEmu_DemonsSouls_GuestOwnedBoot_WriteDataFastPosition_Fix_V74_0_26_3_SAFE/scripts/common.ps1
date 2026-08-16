Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-RepoV740263 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $RepositoryRoot=(Get-Location).Path
    }
    $root=[IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[IO.Path]::Combine($root,'src','SharpEmu.CLI','SharpEmu.CLI.csproj')
    if(-not [IO.File]::Exists($marker)){
        throw "[V74.0.26.3] Invalid repository root: $root"
    }
    return $root
}

function Get-AgcPathV740263 {
    param([string]$Root)
    $path=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Agc','AgcExports.cs')
    if(-not [IO.File]::Exists($path)){
        throw "[V74.0.26.3] Missing AgcExports.cs: $path"
    }
    return $path
}

function Get-HostMoviePathV740263 {
    param([string]$Root)
    $path=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Media','HostMovieBridge.cs')
    if(-not [IO.File]::Exists($path)){
        throw "[V74.0.26.3] Missing HostMovieBridge.cs: $path"
    }
    return $path
}

function New-SourceCaptureV740263 {
    param(
        [string]$Root,
        [string]$AgcPath,
        [string]$HostMoviePath,
        [string]$Reason
    )
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir=[IO.Path]::Combine(
        $Root,
        "SharpEmu_V74_0_26_3_SOURCE_CAPTURE_$stamp")
    [IO.Directory]::CreateDirectory($dir)|Out-Null

    [IO.File]::Copy(
        $AgcPath,
        [IO.Path]::Combine($dir,'AgcExports.cs'),
        $true)
    [IO.File]::Copy(
        $HostMoviePath,
        [IO.Path]::Combine($dir,'HostMovieBridge.cs'),
        $true)

    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($dir,'SUMMARY.txt'),
        [string[]]@(
            'version=74.0.26.3',
            "reason=$Reason",
            "agc_sha256=$((Get-FileHash -LiteralPath $AgcPath -Algorithm SHA256).Hash)",
            "host_movie_sha256=$((Get-FileHash -LiteralPath $HostMoviePath -Algorithm SHA256).Hash)"
        ),
        [Text.UTF8Encoding]::new($false))

    $zip=$dir+'.zip'
    Compress-Archive `
        -Path ([IO.Path]::Combine($dir,'*')) `
        -DestinationPath $zip `
        -Force

    Write-Host "[V74.0.26.3] SOURCE CAPTURE: $zip" -ForegroundColor Yellow
    return $zip
}
