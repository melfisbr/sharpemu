Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-RepoV740262 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $RepositoryRoot=(Get-Location).Path
    }
    $root=[IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[IO.Path]::Combine($root,'src','SharpEmu.CLI','SharpEmu.CLI.csproj')
    if(-not [IO.File]::Exists($marker)){
        throw "[V74.0.26.2] Invalid repository root: $root"
    }
    return $root
}

function Get-AgcV740262([string]$Root){
    $p=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Agc','AgcExports.cs')
    if(-not [IO.File]::Exists($p)){throw "[V74.0.26.2] Missing AGC: $p"}
    return $p
}

function Get-HostMovieV740262([string]$Root){
    $p=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Media','HostMovieBridge.cs')
    if(-not [IO.File]::Exists($p)){throw "[V74.0.26.2] Missing HostMovieBridge: $p"}
    return $p
}

function Test-MediaReplayDedupeV740262([string]$Text){
    foreach($marker in @(
        'V31.7.9_GUEST_REPLAY_DEDUPE',
        'TrySuppressV3179GuestBootReplay',
        'bink2.guest_replay_deduped',
        'bink2.guest_boot_reconciliation_completed',
        'SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY',
        'ps_studios_logo.bk2',
        'logo_intro.bk2',
        'logo_intro_loop.bk2'
    )){
        if(-not $Text.Contains($marker)){
            return $false
        }
    }
    return $true
}
