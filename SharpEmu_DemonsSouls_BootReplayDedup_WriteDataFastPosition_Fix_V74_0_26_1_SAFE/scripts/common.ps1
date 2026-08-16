Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-RepoV74026 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){ $RepositoryRoot=(Get-Location).Path }
    $root=[IO.Path]::GetFullPath($RepositoryRoot)
    if(-not [IO.File]::Exists([IO.Path]::Combine($root,'src','SharpEmu.CLI','SharpEmu.CLI.csproj'))){
        throw "[V74.0.26.1] Invalid repository root: $root"
    }
    return $root
}
function Get-AgcV74026([string]$Root){
    $p=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Agc','AgcExports.cs')
    if(-not [IO.File]::Exists($p)){throw "[V74.0.26.1] Missing AGC: $p"}; return $p
}
function Get-HostMovieV74026([string]$Root){
    $p=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Media','HostMovieBridge.cs')
    if(-not [IO.File]::Exists($p)){throw "[V74.0.26.1] Missing HostMovieBridge: $p"}; return $p
}
function Get-MediaDedupeStateV74026([string]$Text){
    $old=@'
        if (!string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY"),
                "1",
                StringComparison.Ordinal))
        {
            return false;
        }
'@.TrimEnd()
    $new=@'
        // V31.7.11_HOST_BOOT_REPLAY_DEDUPE_DEFAULT
        // Direct boot has already shown these exact canonical startup assets.
        // Reconciliation is narrow (canonical name + host-presented set + boot
        // window), so dedupe is now the default. Set the variable to 0 to opt out.
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY"),
                "0",
                StringComparison.Ordinal))
        {
            return false;
        }
'@.TrimEnd()
    $oc=([regex]::Matches($Text,[regex]::Escape($old))).Count
    $nc=([regex]::Matches($Text,[regex]::Escape($new))).Count
    if($oc -eq 1 -and $nc -eq 0){return 'Baseline'}
    if($oc -eq 0 -and $nc -eq 1){return 'Applied'}
    return "Unsupported(old=$oc new=$nc)"
}
function Convert-MediaDedupeV74026([string]$Text){
    $state=Get-MediaDedupeStateV74026 -Text $Text
    if($state -eq 'Applied'){return $Text}
    if($state -ne 'Baseline'){throw "[V74.0.26.1] Media dedupe state: $state"}
    $old=@'
        if (!string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY"),
                "1",
                StringComparison.Ordinal))
        {
            return false;
        }
'@.TrimEnd()
    $new=@'
        // V31.7.11_HOST_BOOT_REPLAY_DEDUPE_DEFAULT
        // Direct boot has already shown these exact canonical startup assets.
        // Reconciliation is narrow (canonical name + host-presented set + boot
        // window), so dedupe is now the default. Set the variable to 0 to opt out.
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY"),
                "0",
                StringComparison.Ordinal))
        {
            return false;
        }
'@.TrimEnd()
    $ob=([regex]::Matches($Text,[regex]::Escape('{'))).Count
    $cb=([regex]::Matches($Text,[regex]::Escape('}'))).Count
    $patched=$Text.Replace($old,$new)
    if((Get-MediaDedupeStateV74026 -Text $patched) -ne 'Applied'){throw '[V74.0.26.1] Media transform verification failed.'}
    foreach($m in @('V31.7.9_GUEST_REPLAY_DEDUPE','TrySuppressV3179GuestBootReplay','bink2.guest_replay_deduped','bink2.guest_boot_reconciliation_completed')){
        if(-not $patched.Contains($m)){throw "[V74.0.26.1] Existing media marker disappeared: $m"}
    }
    if($ob -ne ([regex]::Matches($patched,[regex]::Escape('{'))).Count -or
       $cb -ne ([regex]::Matches($patched,[regex]::Escape('}'))).Count){
        throw '[V74.0.26.1] Media transform changed brace count.'
    }
    return $patched
}
